import LLMClient
import LLMCloudClient
import LLMTool
import LLMChat
import APIClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI 互換 API の全ロジックを集約するエンジン
///
/// 各 OpenAI 互換クライアントは、このエンジンのインスタンスを保持して
/// プロトコルのデフォルト実装から呼び出す。
package struct OpenAICompatibleEngine: Sendable {
    /// 内部プロバイダー（RetryableProvider でラップ済み）
    package let provider: any LLMProvider

    /// contract 経由の直接送信用。chat/planToolCalls は単発送信、
    /// executeAgentStep は RetryRunner でラップしてリトライする。
    let baseProvider: OpenAICompatibleProvider

    /// API キー
    package let apiKey: String

    /// エンドポイント URL
    package let endpoint: URL

    /// URLSession
    package let session: URLSession

    /// プロバイダー名（エラーメッセージ用）
    package let providerName: String

    /// カスタム HTTP ヘッダー
    package let customHeaders: [String: String]

    /// リトライ設定
    package let retryConfiguration: RetryConfiguration

    /// リトライイベントハンドラー
    package let retryEventHandler: RetryEventHandler?

    private static let defaultMaxTokens = 4096

    package init(
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, providerName: providerName,
            session: session, customHeaders: customHeaders,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    /// Transport を注入する指定イニシャライザ（テストで MockTransport を差し込む）。
    package init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.providerName = providerName
        self.session = session
        self.customHeaders = customHeaders
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler

        let baseProvider = OpenAICompatibleProvider(
            transport: transport,
            apiKey: apiKey,
            endpoint: endpoint,
            providerName: providerName,
            customHeaders: customHeaders
        )
        self.baseProvider = baseProvider

        if retryConfiguration.isEnabled {
            self.provider = RetryableProvider(
                provider: baseProvider,
                extractorType: OpenAICompatibleRateLimitExtractor.self,
                retryPolicy: retryConfiguration.policy,
                eventHandler: retryEventHandler
            )
        } else {
            self.provider = baseProvider
        }
    }

    // MARK: - StructuredLLMClient

    package func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        modelId: String,
        toLLMModel: @Sendable () -> LLMModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await generateWithUsage(
            messages: [input.toLLMMessage()],
            modelId: modelId,
            toLLMModel: toLLMModel,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    package func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        modelId: String,
        toLLMModel: @Sendable () -> LLMModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        let enhancedSystemPrompt = buildSystemPrompt(base: systemPrompt, schema: T.jsonSchema)

        let request = LLMRequest(
            model: toLLMModel(),
            messages: messages,
            systemPrompt: enhancedSystemPrompt,
            responseSchema: T.jsonSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let response = try await provider.send(request)
        return try OpenAICompatibleResponseConverter.toGenerationResult(response, model: modelId)
    }

    // MARK: - ChatCapableClient

    package func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: String?,
        responseSchema: JSONSchema,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        // 全ての送信を api-client(contract)経由に統一（生 URLSession を撤廃）。
        // buildRequestBody が schema 適合・制約プロンプト合成・max_completion_tokens を
        // 一貫処理し、エラーは contract の decodeError がリッチにマッピングする。
        let request = LLMRequest(
            model: .custom(modelId),
            messages: messages,
            systemPrompt: systemPrompt,
            responseSchema: responseSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )
        let (output, _, _) = try await baseProvider.sendRaw(request)
        return try OpenAICompatibleResponseConverter.toChatResponse(output)
    }

    // MARK: - ToolCallableClient

    package func planToolCalls(
        messages: [LLMMessage],
        modelId: String,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        var openAIMessages: [OpenAICompatibleMessage] = []

        if let systemPrompt = systemPrompt {
            openAIMessages.append(OpenAICompatibleMessage(
                role: "system", content: systemPrompt, toolCallId: nil, toolCalls: nil
            ))
        }

        for message in messages {
            openAIMessages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        let body = OpenAICompatibleRequestBody(
            model: modelId,
            messages: openAIMessages,
            maxCompletionTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: temperature,
            responseFormat: nil,
            tools: tools.toOpenAIToolDefs(),
            toolChoice: toolChoice.map { mapToolChoice($0) }
        )
        // 生 URLSession を撤廃し contract 経由に統一（ボディは既に max_completion_tokens）。
        let (output, _, _) = try await baseProvider.sendBody(body)
        return OpenAICompatibleResponseConverter.toToolCallResponse(output)
    }

    // MARK: - AgentCapableClient

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
        var openAIMessages: [OpenAICompatibleMessage] = []

        if let prompt = systemPrompt {
            openAIMessages.append(OpenAICompatibleMessage(
                role: "system", content: prompt.render(), toolCallId: nil, toolCalls: nil
            ))
        }

        for message in messages {
            openAIMessages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        let openAITools: [OpenAICompatibleToolDef]? = tools.isEmpty ? nil : tools.toOpenAIToolDefs()
        let openAIToolChoice: OpenAICompatibleToolChoice? = tools.isEmpty ? nil : (toolChoice.map { mapToolChoice($0) } ?? .auto)

        var responseFormat: OpenAICompatibleResponseFormat?
        if let schema = responseSchema {
            let adapter = OpenAISchemaAdapter()
            responseFormat = OpenAICompatibleResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAICompatibleJSONSchemaWrapper(
                    name: "response",
                    strict: true,
                    schema: adapter.adapt(schema)
                )
            )
        }

        let body = OpenAICompatibleRequestBody(
            model: modelId,
            messages: openAIMessages,
            maxCompletionTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: nil,
            responseFormat: responseFormat,
            tools: openAITools,
            toolChoice: openAIToolChoice,
            reasoningEffort: reasoningEffort?.rawValue
        )

        // 生 URLSession + AgentRetryHelper を撤廃し contract 経由に統一。
        // リトライはドメイン認識の RetryRunner に集約（RetryableProvider と同一実装）。
        let output = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await baseProvider.sendBody(body).0
        }
        return OpenAICompatibleResponseConverter.toLLMResponse(output)
    }

    // MARK: - Private Helpers

    private func buildSystemPrompt(base: String?, schema: JSONSchema) -> String {
        var parts: [String] = []

        if let base = base {
            parts.append(base)
        }

        if let description = schema.description {
            parts.append("出力形式: \(description)")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    private func mapToolChoice(_ choice: ToolChoice) -> OpenAICompatibleToolChoice {
        switch choice {
        case .auto:
            return .auto
        case .disabled:
            return .none
        case .required:
            return .required
        case .tool(let name):
            return .function(name)
        }
    }
}
