import Foundation
import LLMClient
import LLMAgentStep
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool
import APIClient
import APIContract
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
    package let customHeaders: [String: String]
    package let retryConfiguration: RetryConfiguration
    package let retryEventHandler: RetryEventHandler?

    /// `/v1/responses` 専用の APIClient。キー変換なし(`.default`)で、リクエスト/レスポンス
    /// 双方の明示的 CodingKeys をそのまま尊重する。
    private let apiClient: APIClientImpl

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
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, customHeaders: customHeaders,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    /// Transport を注入する指定イニシャライザ（テストで MockTransport を差し込む）。
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

        // 生 URLSession + AgentRetryHelper を撤廃し contract 経由に統一。
        // リトライはドメイン認識の RetryRunner に集約（chat 系と同一実装）。
        let responseBody = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.sendBody(body)
        }
        return OpenAIResponsesConverter.toLLMResponse(responseBody)
    }

    // MARK: - Private

    /// リクエストボディを contract 経由で送信し、デコード済みレスポンスボディを返す。
    /// エラーは contract の decodeError(リッチ)と APIError マッピングで統一する。
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
