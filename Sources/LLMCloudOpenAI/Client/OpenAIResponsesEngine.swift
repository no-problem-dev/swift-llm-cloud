import Foundation
import LLMClient
import LLMAgentStep
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool
import APIClient
import APIContract
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Engine that talks to the OpenAI Responses API.
///
/// It exists alongside the Chat Completions based ``OpenAICompatibleEngine``. ``OpenAIClient``
/// routes to it when a reasoning model is combined with function tools, which Chat Completions
/// refuses, and for every streaming call.
///
/// Design decisions:
/// - **Stateless**: `store` is always false and `previous_response_id` is never sent, so OpenAI
///   keeps no server-side copy of the conversation. Callers such as the agent loop runner keep
///   passing the whole history as `[LLMMessage]` on each turn, which preserves the existing
///   contract with the Chat Completions path.
/// - **Two request paths**: the non-streaming step returns the finished response in one piece
///   and is retried; the streaming step consumes named SSE events and is not.
package struct OpenAIResponsesEngine: Sendable {
    package let customHeaders: [String: String]
    package let retryConfiguration: RetryConfiguration
    package let retryEventHandler: RetryEventHandler?

    /// API client bound to the Responses endpoint, with key conversion turned off.
    ///
    /// The request and response types spell out their own coding keys, so snake-case conversion
    /// has to stay off — enabling it would mangle keys such as `max_output_tokens` and `call_id`.
    private let apiClient: APIClientImpl

    /// Responses API URL used when no custom endpoint is supplied.
    package static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    /// Value sent as `max_output_tokens` when the caller passes no limit.
    ///
    /// On reasoning models this budget covers reasoning tokens as well as visible output, so a
    /// step that thinks hard can hit the cap before it emits any text.
    package static let defaultMaxOutputTokens = 4096

    package init(
        apiKey: String,
        endpoint: URL = defaultEndpoint,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, customHeaders: customHeaders,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    /// Designated initializer that takes an injected transport, which lets tests supply a mock.
    package init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL = defaultEndpoint,
        customHeaders: [String: String] = [:],
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.customHeaders = customHeaders
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler
        self.apiClient = APIClientImpl(
            baseURL: endpoint,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .default
        )
    }

    /// Runs one agent step and waits for the finished response.
    ///
    /// The messages are flattened into Responses input items, tools become flat function
    /// definitions with `strict` set, and a response schema is sent as `text.format` rather than
    /// as the Chat Completions `response_format`. When `maxTokens` is nil the request falls back
    /// to ``defaultMaxOutputTokens``.
    ///
    /// Failures are retried by the shared retry runner, which prefers the delay derived from the
    /// `retry-after` and `x-ratelimit-*` headers over its own backoff.
    package func executeAgentStep(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        let inputItems = try OpenAIResponsesConverter.toInputItems(messages)
        let toolDefs: [OpenAIResponsesToolDef]? = tools.isEmpty
            ? nil
            : OpenAIResponsesConverter.toToolDefs(tools)
        let resolvedToolChoice = OpenAIResponsesConverter.toToolChoice(toolChoice, hasTools: !tools.isEmpty)

        let textConfig: OpenAIResponsesTextConfig? = responseSchema.map { schema in
            let adapter = OpenAISchemaAdapter()
            return OpenAIResponsesTextConfig(
                format: OpenAIResponsesFormat(
                    name: "response",
                    schema: adapter.adapt(schema),
                    strict: true
                )
            )
        }

        let body = OpenAIResponsesRequestBody(
            model: modelId,
            instructions: systemPrompt?.render(),
            input: inputItems,
            tools: toolDefs,
            toolChoice: resolvedToolChoice,
            reasoning: reasoningEffort.map { OpenAIResponsesReasoningConfig(effort: $0) },
            text: textConfig,
            maxOutputTokens: maxTokens ?? Self.defaultMaxOutputTokens,
            store: false
        )

        // The request goes through the contract, and retries live in the domain-aware
        // RetryRunner — the same implementation the Chat Completions path uses.
        let responseBody = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.sendBody(body)
        }
        return OpenAIResponsesConverter.toLLMResponse(responseBody)
    }

    /// Runs one agent step and yields events as the response streams in.
    ///
    /// Each SSE payload is dispatched on the `type` field inside its `data:` JSON, not on the
    /// `event:` line: `response.output_text.delta` is yielded as a text delta and
    /// `response.reasoning_text.delta` as a thinking delta. Every other named event is dropped,
    /// including `response.function_call_arguments.delta` — the ground truth is the complete
    /// Response carried by `response.completed`, which goes through the same conversion as the
    /// non-streaming path, so tool-call arguments never have to be reassembled from deltas.
    ///
    /// A `response.failed` or `response.incomplete` event finishes the stream with a server
    /// error. This path is never retried: replaying a stream that broke midway would repeat the
    /// deltas the caller already consumed.
    package func streamAgentStep(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        makeCancellableStream { continuation in
            Task {
                do {
                    try await self.executeStreamingAgentStep(
                        messages: messages,
                        modelId: modelId,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        toolChoice: toolChoice,
                        responseSchema: responseSchema,
                        reasoningEffort: reasoningEffort,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func executeStreamingAgentStep(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        continuation: AsyncThrowingStream<StreamingAgentEvent, Error>.Continuation
    ) async throws {
        let inputItems = try OpenAIResponsesConverter.toInputItems(messages)
        let toolDefs: [OpenAIResponsesToolDef]? = tools.isEmpty
            ? nil
            : OpenAIResponsesConverter.toToolDefs(tools)
        let resolvedToolChoice = OpenAIResponsesConverter.toToolChoice(toolChoice, hasTools: !tools.isEmpty)

        let textConfig: OpenAIResponsesTextConfig? = responseSchema.map { schema in
            let adapter = OpenAISchemaAdapter()
            return OpenAIResponsesTextConfig(
                format: OpenAIResponsesFormat(
                    name: "response",
                    schema: adapter.adapt(schema),
                    strict: true
                )
            )
        }

        let body = OpenAIResponsesRequestBody(
            model: modelId,
            instructions: systemPrompt?.render(),
            input: inputItems,
            tools: toolDefs,
            toolChoice: resolvedToolChoice,
            reasoning: reasoningEffort.map { OpenAIResponsesReasoningConfig(effort: $0) },
            text: textConfig,
            maxOutputTokens: maxTokens ?? Self.defaultMaxOutputTokens,
            store: false,
            stream: true
        )

        let contract = OpenAIResponsesAPI.CreateResponse(customHeaders: customHeaders, request: body)
        var completed = false
        for try await sse in apiClient.executeEventStream(contract) {
            switch OpenAIResponsesStreamEvent(data: sse.data) {
            case .outputTextDelta(let delta):
                continuation.yield(.delta(.textDelta(delta)))
            case .reasoningTextDelta(let delta):
                continuation.yield(.delta(.thinkingDelta(delta)))
            case .completed(let response):
                guard !completed else { break }
                completed = true
                continuation.yield(.completed(OpenAIResponsesConverter.toLLMResponse(response)))
            case .failed(let message):
                continuation.finish(throwing: LLMError.serverError(0, message))
                return
            case .ignored:
                break
            }
        }
        continuation.finish()
    }

    // MARK: - Private

    /// Sends the request body through the contract and returns the decoded response body.
    ///
    /// Errors the contract already shaped — `LLMError` and the rate-limit-aware wrapper the
    /// group builds for 429 and 5xx — are rethrown untouched so the retry runner can read the
    /// wait the server asked for. A transport-level `APIError` is mapped onto `LLMError`, and
    /// anything else is wrapped as a network error.
    private func sendBody(_ body: OpenAIResponsesRequestBody) async throws -> OpenAIResponsesResponseBody {
        let contract = OpenAIResponsesAPI.CreateResponse(customHeaders: customHeaders, request: body)
        do {
            return try await apiClient.executeWithResponse(contract).output
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
}
