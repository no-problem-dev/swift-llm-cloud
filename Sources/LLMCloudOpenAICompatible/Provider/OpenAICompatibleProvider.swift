import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Single provider shared by every vendor that speaks the OpenAI Chat Completions wire format.
///
/// DeepSeek, Groq, Mistral, OpenRouter, and xAI all run on this type; the vendor differences are
/// injected rather than subclassed — the full endpoint URL, any extra headers, and whether the
/// token cap goes out as `max_completion_tokens` or `max_tokens`. Every call goes through
/// `APIClientImpl` and the `CreateChatCompletion` contract, so error decoding and rate-limit
/// header handling are identical for all of them — streamed and non-streamed alike.
package struct OpenAICompatibleProvider: LLMProvider, RetryableProviderProtocol {
    private let apiClient: APIClientImpl

    /// Vendor name reported in unsupported-media errors raised while converting messages.
    private let providerName: String

    /// Headers added to every request, such as OpenRouter's `X-Title` and `HTTP-Referer`.
    private let customHeaders: [String: String]

    /// Which field name carries the token cap for this vendor.
    private let maxTokensParameter: OpenAICompatibleMaxTokensParameter

    /// Full chat-completions URL, also used when synthesizing a response object for the retry layer.
    private let endpoint: URL

    /// Token cap sent when the caller's request does not specify one.
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// Creates a provider that talks to one vendor's chat-completions endpoint.
    ///
    /// - Parameters:
    ///   - apiKey: Sent as `Authorization: Bearer`.
    ///   - endpoint: The complete URL, including the path — nothing is appended to it.
    ///   - providerName: Vendor name used in unsupported-media error messages.
    ///   - session: Session backing the default URLSession transport.
    ///   - customHeaders: Headers added to every request.
    ///   - maxTokensParameter: Field name for the token cap. Mistral, DeepSeek, and OpenRouter
    ///     need `max_tokens`; the default suits Groq and xAI.
    package init(
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, providerName: providerName,
            customHeaders: customHeaders, maxTokensParameter: maxTokensParameter
        )
    }

    /// Designated initializer taking an injected transport, so tests can substitute a mock.
    package init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL,
        providerName: String,
        customHeaders: [String: String] = [:],
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens
    ) {
        self.providerName = providerName
        self.customHeaders = customHeaders
        self.maxTokensParameter = maxTokensParameter
        self.endpoint = endpoint
        self.apiClient = APIClientImpl(
            baseURL: endpoint,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .snakeCase
        )
    }

    // MARK: - LLMProvider

    package func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    package func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        let (output, statusCode, headers) = try await sendRaw(request)
        let llmResponse = OpenAICompatibleResponseConverter.toLLMResponse(output)
        // Rebuild an HTTPURLResponse: the retry layer reads rate-limit headers off it.
        let httpResponse = HTTPURLResponse(
            url: endpoint, statusCode: statusCode, httpVersion: nil, headerFields: headers
        )!
        return (llmResponse, httpResponse)
    }

    /// Sends a request through the chat-completions contract and returns the undecorated body.
    ///
    /// This is the single HTTP path every non-streaming call takes — `send`, `chat`, and
    /// `planToolCalls` all end up here — so vendor error bodies are decoded the same way and the
    /// caller always gets the headers needed to read rate-limit state.
    ///
    /// - Returns: The decoded response body, the HTTP status code, and the response headers.
    package func sendRaw(_ request: LLMRequest) async throws -> (OpenAICompatibleResponseBody, Int, [String: String]) {
        try await sendBody(buildRequestBody(from: request))
    }

    /// Sends an already-built body, for requests carrying more than the shared request can express.
    ///
    /// Tool definitions, `tool_choice`, and `reasoning_effort` come in this way. `LLMError` and
    /// `RateLimitAwareError` raised by the contract's error decoder are rethrown untouched so the
    /// retry layer still sees the rate-limit info; any other `APIError` is mapped to an `LLMError`,
    /// and anything left is wrapped as `LLMError.networkError`.
    ///
    /// - Returns: The decoded response body, the HTTP status code, and the response headers.
    package func sendBody(_ body: OpenAICompatibleRequestBody) async throws -> (OpenAICompatibleResponseBody, Int, [String: String]) {
        let contract = OpenAICompatibleAPI.CreateChatCompletion(customHeaders: customHeaders, request: body)
        do {
            let apiResponse = try await apiClient.executeWithResponse(contract)
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

    /// Opens a streamed chat completion and yields the vendor's SSE frames.
    ///
    /// The body must already carry `stream: true`; nothing is added here. Frames arrive exactly as
    /// the vendor sent them, including the `data: [DONE]` terminator, which the caller skips —
    /// unlike the typed `execute` path, this one does no filtering. OpenRouter's `:` keepalive
    /// comments never reach here at all: the SSE parser drops comment lines per the spec.
    ///
    /// Errors are shaped exactly as on the non-streaming path, so a 429 still arrives as a
    /// `RateLimitAwareError` carrying the vendor's headers. Nothing is retried, though: replaying a
    /// stream that broke midway would repeat deltas the caller has already consumed.
    ///
    /// - Parameter body: Request body with `stream` set.
    /// - Returns: The vendor's SSE frames, in order.
    package func streamChatCompletionEvents(
        _ body: OpenAICompatibleRequestBody
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let contract = OpenAICompatibleAPI.CreateChatCompletion(customHeaders: customHeaders, request: body)
        return apiClient.executeEventStream(contract)
    }

    // MARK: - Request Building

    /// Builds the wire body, moving schema constraints the vendor drops into the system prompt.
    ///
    /// A response schema is sent as `response_format.json_schema` with `strict: true`, which forces
    /// most JSON Schema keywords out of the schema. The adapter reports what it removed, and those
    /// constraints are appended to the system prompt as instructions instead — otherwise a
    /// `minimum` or `pattern` would silently stop being enforced.
    private func buildRequestBody(from request: LLMRequest) throws -> OpenAICompatibleRequestBody {
        var messages: [OpenAICompatibleMessage] = []

        var responseFormat: OpenAICompatibleResponseFormat?
        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = OpenAISchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            responseFormat = OpenAICompatibleResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAICompatibleJSONSchemaWrapper(
                    name: "response",
                    strict: true,
                    schema: adaptationResult.schema
                )
            )

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        let effectiveSystemPrompt = composeSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        if let systemPrompt = effectiveSystemPrompt {
            messages.append(OpenAICompatibleMessage(
                role: "system",
                content: systemPrompt,
                toolCallId: nil,
                toolCalls: nil
            ))
        }

        for message in request.messages {
            messages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        return OpenAICompatibleRequestBody(
            model: request.model.id,
            messages: messages,
            maxCompletionTokens: request.maxTokens ?? Self.defaultMaxTokens,
            maxTokensParameter: maxTokensParameter,
            temperature: request.temperature,
            responseFormat: responseFormat,
            tools: nil,
            toolChoice: nil
        )
    }


    // MARK: - Error Mapping
}

// MARK: - Static Token Provider
