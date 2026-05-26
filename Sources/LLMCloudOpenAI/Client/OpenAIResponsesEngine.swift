import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI `/v1/responses` API を呼び出すための専用エンジン。
///
/// Chat Completions ベースの `OpenAICompatibleEngine` と並行して存在し、
/// `OpenAIClient` 内で「reasoning_effort + function tools が同時に必要」な
/// ケースに限り routing される。
///
/// 設計判断:
/// - **Stateless**: `store: false` 固定、`previous_response_id` は使わない。
///   呼び出し側（AgentLoopRunner 等）が会話履歴を `[LLMMessage]` として
///   毎ターン渡してくる既存契約を維持する。
/// - **Non-streaming**: 既存 `executeAgentStep` と同様に完了レスポンスをまとめて返す。
///   ストリーミング API は別パスとして将来追加する。
package struct OpenAIResponsesEngine: Sendable {
    package let apiKey: String
    package let endpoint: URL
    package let session: URLSession
    package let customHeaders: [String: String]
    package let retryConfiguration: RetryConfiguration
    package let retryEventHandler: RetryEventHandler?

    /// `/v1/responses` のデフォルト URL。
    package static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    /// デフォルトの最大出力トークン数。
    package static let defaultMaxOutputTokens = 4096

    package init(
        apiKey: String,
        endpoint: URL = defaultEndpoint,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
        self.customHeaders = customHeaders
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler
    }

    /// エージェントステップを実行する。
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
        let inputItems = OpenAIResponsesConverter.toInputItems(messages)
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

        var urlRequest = makeURLRequest()
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let retryHelper = AgentRetryHelper<OpenAICompatibleRateLimitExtractor>(
            configuration: retryConfiguration,
            eventHandler: retryEventHandler
        )

        return try await retryHelper.execute(
            session: session,
            request: urlRequest,
            parseError: { data, statusCode in
                Self.parseError(data: data, statusCode: statusCode)
            },
            parseResponse: { data, _ in
                try Self.parseSuccess(data: data)
            }
        )
    }

    // MARK: - Private

    private func makeURLRequest() -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (key, value) in customHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }

    private static func parseError(data: Data, statusCode: Int) -> LLMError {
        let message = (try? JSONDecoder().decode(OpenAIResponsesErrorBody.self, from: data))?
            .error.message
            ?? String(data: data, encoding: .utf8)
            ?? "Unknown error"

        switch statusCode {
        case 401:
            return .unauthorized
        case 429:
            return .rateLimitExceeded
        case 400:
            return .invalidRequest(message)
        case 404:
            return .modelNotFound(message)
        case 500...599:
            return .serverError(statusCode, message)
        default:
            return .serverError(statusCode, message)
        }
    }

    private static func parseSuccess(data: Data) throws -> LLMResponse {
        let decoder = JSONDecoder()
        let body: OpenAIResponsesResponseBody
        do {
            body = try decoder.decode(OpenAIResponsesResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }
        return OpenAIResponsesConverter.toLLMResponse(body)
    }
}
