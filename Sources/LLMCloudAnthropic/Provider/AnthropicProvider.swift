import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicProvider

/// Transport-level implementation of the Anthropic Messages API.
///
/// Held privately by ``AnthropicClient``; when retries are enabled the client wraps this in a
/// retrying provider, so reaching this type directly means no retry, no backoff, and no reading
/// of the `anthropic-ratelimit-*` headers.
internal struct AnthropicProvider: LLMProvider, RetryableProviderProtocol {
    /// Shared with the count_tokens extension in this module, which posts to a sibling path.
    let apiClient: APIClientImpl

    /// Output limit sent when a request leaves one unset, since Anthropic requires it.
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// Creates a provider for the given API key.
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API key, sent in the `x-api-key` header.
    ///   - baseURL: Host root the `/v1/messages` paths are appended to. Defaults to the public
    ///     Anthropic API.
    ///   - session: Session backing the default transport.
    init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.init(transport: URLSessionTransport(session: session), apiKey: apiKey, baseURL: baseURL)
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        baseURL: URL? = nil
    ) {
        let effectiveBaseURL = baseURL ?? URL(string: "https://api.anthropic.com")!
        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .snakeCase
        )
    }

    /// Sends a streaming request and yields the raw server-sent events.
    ///
    /// Nothing is interpreted here: the caller receives `message_start`, `content_block_start`,
    /// `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`, and `error`
    /// events verbatim and assembles them itself. Usage arrives split across two of them —
    /// input and cache counts on `message_start`, final output count on `message_delta`.
    func streamMessageEvents(_ body: AnthropicRequestBody, beta: [String] = []) -> AsyncThrowingStream<SSEEvent, Error> {
        apiClient.executeEventStream(AnthropicAPI.CreateMessage(beta: beta, request: body))
    }

    /// Sends an already-built request body and returns the reply with its status and headers.
    ///
    /// Used for requests the generic send path cannot express, such as tool definitions and tool
    /// choice. The headers come back so the caller can read the `anthropic-ratelimit-*` values;
    /// note that this call performs no retry of its own.
    func sendBody(_ body: AnthropicRequestBody, beta: [String] = []) async throws -> (AnthropicResponseBody, Int, [String: String]) {
        let endpoint = AnthropicAPI.CreateMessage(beta: beta, request: body)
        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)
            return (apiResponse.output, apiResponse.statusCode, apiResponse.headers)
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

    // MARK: - LLMProvider

    func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    /// Sends a request and returns the reply alongside a response object the retry layer reads.
    ///
    /// The second element is synthesized from the status code and headers so the retry wrapper
    /// can extract Anthropic's rate limit state; its URL is the canonical messages endpoint even
    /// when a custom base URL was configured, so do not treat it as the address actually called.
    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        guard case .claude = request.model else {
            throw LLMError.modelNotSupported(model: request.model.id, provider: "Anthropic")
        }

        let body = try buildRequestBody(from: request)

        // Structured output needs no beta flag. Only file_id references and the one-hour cache
        // TTL do, and only when the request actually uses them.
        let endpoint = AnthropicAPI.CreateMessage(beta: Self.betaValues(for: request) + body.cacheBetaValues, request: body)

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)

            let llmResponse = try convertToLLMResponse(apiResponse.output)

            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
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

    /// Lowers a provider-neutral request into the Anthropic body shape.
    ///
    /// A response schema becomes an `output_config.format` of type `json_schema`. Constraints
    /// Anthropic cannot enforce during constrained decoding are stripped from the schema by the
    /// adapter and restated in prose in the system prompt instead, so they are not silently
    /// lost. Since Anthropic requires `max_tokens`, a request without one is given 4096.
    private func buildRequestBody(from request: LLMRequest) throws -> AnthropicRequestBody {
        let messages = try request.messages.map { message in
            try AnthropicMessageConverter.convert(message)
        }

        var outputFormat: AnthropicOutputFormat?
        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = AnthropicSchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            outputFormat = AnthropicOutputFormat(
                type: "json_schema",
                schema: adaptationResult.schema
            )

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        let effectiveSystemPrompt = composeSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        return AnthropicRequestBody(
            model: request.model.id,
            messages: messages,
            system: effectiveSystemPrompt,
            maxTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: request.temperature,
            outputConfig: outputFormat.map { AnthropicOutputConfig(format: $0) },
            cachePolicy: request.cachePolicy
        )
    }

    /// Beta feature name required to reference uploaded files by id.
    static let filesAPIBeta = "files-api-2025-04-14"

    /// Returns the beta names a request needs, currently only the Files API opt-in.
    ///
    /// The header is added only when some image or document is passed by `file_id` rather than
    /// inline base64 or a URL, so ordinary requests carry no beta flag.
    static func betaValues(for request: LLMRequest) -> [String] {
        betaValues(for: request.messages)
    }

    static func betaValues(for messages: [LLMMessage]) -> [String] {
        let usesFileReference = messages.contains { message in
            message.contents.contains { content in
                switch content {
                case .image(let image): return image.source.isFileReference
                case .document(let document): return document.source.isFileReference
                default: return false
                }
            }
        }
        return usesFileReference ? [filesAPIBeta] : []
    }

    // MARK: - Response Conversion

    /// Converts a reply into the provider-neutral response shape.
    ///
    /// Text and tool-use blocks survive; thinking blocks and unrecognized block types are
    /// dropped, so this path never surfaces reasoning. A tool use missing its id, name, or input
    /// is skipped rather than failing the whole reply. An empty result throws
    /// `LLMError.emptyResponse` unless the turn stopped for tool use, which legitimately
    /// produces no content. Usage is normalized so cached tokens are folded into the input
    /// count.
    private func convertToLLMResponse(_ response: AnthropicResponseBody) throws -> LLMResponse {
        let stopReason = response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        let contentBlocks = try response.content.compactMap { block -> LLMResponse.ContentBlock? in
            switch AnthropicBlockType(rawValue: block.type) {
            case .text:
                return block.text.map { .text($0) }
            case .toolUse:
                guard let id = block.id, let name = block.name, let input = block.input else {
                    return nil
                }
                let inputData = try JSONEncoder().encode(input)
                return .toolUse(id: id, name: name, input: inputData)
            case .thinking, nil:
                return nil
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: stopReason
        )
    }

}

// MARK: - Static Token Provider
