import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
import StructuredDataCore
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiProvider

/// Transport-level implementation of the Gemini generative language API.
///
/// Speaks the wire protocol through the shared contract layer and is used from inside
/// ``GeminiClient``; retries, prompt caching, and tool calling are layered on above it. The
/// generic `send` path here always sends the system instruction inline and declares no tools, so
/// tool-calling and cached-prefix requests go through the client's own builders instead.
internal struct GeminiProvider: LLMProvider, RetryableProviderProtocol {
    private let apiClient: APIClientImpl

    /// Output cap applied when the caller names none, since Gemini otherwise uses the model default.
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// Creates a provider pointed at the Gemini models endpoint.
    ///
    /// - Parameters:
    ///   - apiKey: Google AI API key, sent as the `x-goog-api-key` header.
    ///   - baseURL: Overrides the default models base URL.
    ///   - session: URLSession backing the default transport.
    init(
        apiKey: String,
        baseURL: String? = nil,
        session: URLSession = .shared
    ) {
        self.init(transport: URLSessionTransport(session: session), apiKey: apiKey, baseURL: baseURL)
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        baseURL: String? = nil
    ) {
        let effectiveBaseURL = URL(string: baseURL ?? "https://generativelanguage.googleapis.com/v1beta/models")!
        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey)
        )
    }

    /// Streams the raw SSE events of `streamGenerateContent`, leaving parsing to the caller.
    ///
    /// Each event's data is a whole response body rather than a delta, so text has to be
    /// accumulated and usage counters overwritten rather than summed.
    func streamContentEvents(_ body: GeminiRequestBody, modelId: String) -> AsyncThrowingStream<SSEEvent, Error> {
        apiClient.executeEventStream(GeminiAPI.StreamGenerateContent(modelId: modelId, request: body))
    }

    /// Sends an already-built request body and returns the decoded body with its status and headers.
    ///
    /// Cache errors pass through untouched so the caller's recovery can act on them; other API
    /// errors are mapped to the shared error type.
    func sendBody(_ body: GeminiRequestBody, modelId: String) async throws -> (GeminiResponseBody, Int, [String: String]) {
        let endpoint = GeminiAPI.GenerateContent(modelId: modelId, request: body)
        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)
            return (apiResponse.output, apiResponse.statusCode, apiResponse.headers)
        } catch let error as LLMError {
            throw error
        } catch let error as RateLimitAwareError {
            throw error
        } catch let error as GeminiCachedContentError {
            throw error // Cache loss is handled by the caller's recovery path.
        } catch let error as APIError {
            throw mapAPIErrorToLLMError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    // MARK: - LLMProvider

    func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        guard case .gemini = request.model else {
            throw LLMError.modelNotSupported(model: request.model.id, provider: "Gemini")
        }

        let body = try buildRequestBody(from: request)

        let endpoint = GeminiAPI.GenerateContent(
            modelId: request.model.id,
            request: body
        )

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)

            let llmResponse = try convertToLLMResponse(apiResponse.output, model: request.model.id)

            // Rebuild an HTTPURLResponse so the retry layer can read the response headers.
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                statusCode: apiResponse.statusCode,
                httpVersion: nil,
                headerFields: apiResponse.headers
            )!

            return (llmResponse, httpResponse)
        } catch let error as LLMError {
            throw error
        } catch let error as RateLimitAwareError {
            throw error
        } catch let error as APIError {
            throw mapAPIErrorToLLMError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    // MARK: - Request Building

    /// Builds the request body for a generic request, with the prefix always sent inline.
    ///
    /// A response schema is adapted to Gemini's OpenAPI subset first, and the constraints that
    /// subset cannot express are restated in the system instruction so the model still honours
    /// them. This path declares no tools and never references a cache.
    private func buildRequestBody(from request: LLMRequest) throws -> GeminiRequestBody {
        var contents: [GeminiContent] = []

        for message in request.messages {
            contents.append(contentsOf: GeminiContentConverter.convert(message))
        }

        var generationConfig = GeminiGenerationConfig(
            maxOutputTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: request.temperature
        )

        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = GeminiSchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            generationConfig.responseMimeType = "application/json"
            generationConfig.responseSchema = adaptationResult.schema

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        let effectiveSystemPrompt = composeSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        var systemInstruction: GeminiContent?
        if let systemPrompt = effectiveSystemPrompt {
            systemInstruction = GeminiContent(
                role: "user",
                parts: [GeminiPart(text: systemPrompt)]
            )
        }

        return GeminiRequestBody(
            contents: contents,
            generationConfig: generationConfig,
            promptContext: .inline(systemInstruction: systemInstruction, tools: nil, toolConfig: nil)
        )
    }

    // MARK: - Response Conversion

    /// Converts a Gemini response body into the shared response shape.
    ///
    /// Only the first candidate is read. Text parts and function calls become content blocks in
    /// the order Gemini sent them; because Gemini issues no tool-call ids, a fresh UUID stands in
    /// for one here. Usage is normalized so cached and reasoning tokens are not double-counted.
    ///
    /// - Throws: `LLMError.contentBlocked` when the prompt was refused, and
    ///   `LLMError.emptyResponse` when nothing usable came back.
    private func convertToLLMResponse(_ response: GeminiResponseBody, model: String) throws -> LLMResponse {
        guard let candidate = response.candidates?.first else {
            if let promptFeedback = response.promptFeedback,
               let blockReason = promptFeedback.blockReason {
                throw LLMError.contentBlocked(reason: blockReason)
            }
            throw LLMError.emptyResponse
        }

        let stopReason = mapStopReason(candidate.finishReason)

        var contentBlocks: [LLMResponse.ContentBlock] = []

        if let content = candidate.content {
            for part in content.parts {
                if let text = part.text {
                    contentBlocks.append(.text(text))
                }
                if let functionCall = part.functionCall {
                    let argsData = (functionCall.args.flatMap { try? JSONEncoder().encode($0) }) ?? Data("{}".utf8)
                    contentBlocks.append(.toolUse(
                        id: UUID().uuidString,
                        name: functionCall.name,
                        input: argsData
                    ))
                }
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        let usage: TokenUsage
        if let usageMetadata = response.usageMetadata {
            usage = GeminiUsageNormalizer.normalize(usageMetadata)
        } else {
            usage = TokenUsage.zero
        }

        return LLMResponse(
            content: contentBlocks,
            model: model,
            usage: usage,
            stopReason: stopReason
        )
    }

    private func mapStopReason(_ reason: String?) -> LLMResponse.StopReason? {
        GeminiFinishReason.stopReason(reason)
    }
}
