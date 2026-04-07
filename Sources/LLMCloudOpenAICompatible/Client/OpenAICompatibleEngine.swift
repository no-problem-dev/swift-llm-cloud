import LLMClient
import LLMCloudClient
import LLMTool
import LLMChat
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
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.providerName = providerName
        self.session = session
        self.customHeaders = customHeaders
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler

        let baseProvider = OpenAICompatibleProvider(
            apiKey: apiKey,
            endpoint: endpoint,
            providerName: providerName,
            session: session,
            customHeaders: customHeaders
        )

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
        var urlRequest = makeURLRequest()

        var openAIMessages: [OpenAICompatibleMessage] = []

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            openAIMessages.append(OpenAICompatibleMessage(
                role: "system", content: systemPrompt, toolCallId: nil, toolCalls: nil
            ))
        }

        for message in messages {
            openAIMessages.append(OpenAICompatibleMessageConverter.convertSimple(message))
        }

        let adapter = OpenAISchemaAdapter()
        let adaptedSchema = adapter.adapt(responseSchema)
        guard let schemaData = try? adaptedSchema.toJSONData(),
              let schemaDict = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw LLMError.invalidRequest("Failed to convert schema to dictionary")
        }

        let body = OpenAICompatibleChatRequestBody(
            model: modelId,
            messages: openAIMessages,
            temperature: temperature,
            maxTokens: maxTokens,
            responseFormat: OpenAICompatibleChatResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAICompatibleChatJSONSchema(
                    name: "response",
                    strict: true,
                    schema: schemaDict
                )
            )
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidRequest("Invalid response type")
        }

        try handleErrorStatus(data: data, httpResponse: httpResponse)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let openAIResponse: OpenAICompatibleResponseBody
        do {
            openAIResponse = try decoder.decode(OpenAICompatibleResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return try OpenAICompatibleResponseConverter.toChatResponse(openAIResponse)
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
        var urlRequest = makeURLRequest()

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

        let openAITools = tools.toOpenAIFormat().map { OpenAICompatibleToolDef(dict: $0) }
        let openAIToolChoice = toolChoice.map { mapToolChoice($0) }

        let body = OpenAICompatibleRequestBody(
            model: modelId,
            messages: openAIMessages,
            maxCompletionTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: temperature,
            responseFormat: nil,
            tools: openAITools,
            toolChoice: openAIToolChoice
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidRequest("Invalid response type")
        }

        try handleErrorStatus(data: data, httpResponse: httpResponse)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let openAIResponse: OpenAICompatibleResponseBody
        do {
            openAIResponse = try decoder.decode(OpenAICompatibleResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return OpenAICompatibleResponseConverter.toToolCallResponse(openAIResponse)
    }

    // MARK: - AgentCapableClient

    package func executeAgentStep(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        var urlRequest = makeURLRequest()

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

        let openAITools: [OpenAICompatibleToolDef]? = tools.isEmpty ? nil : tools.toOpenAIFormat().map { OpenAICompatibleToolDef(dict: $0) }
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
            toolChoice: openAIToolChoice
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let retryHelper = AgentRetryHelper<OpenAICompatibleRateLimitExtractor>(
            configuration: retryConfiguration,
            eventHandler: retryEventHandler
        )

        return try await retryHelper.execute(
            session: session,
            request: urlRequest,
            parseError: { data, statusCode in
                try parseAgentError(data: data, statusCode: statusCode)
            },
            parseResponse: { data, _ in
                try parseAgentSuccessResponse(data: data)
            }
        )
    }

    // MARK: - Private Helpers

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

    private func handleErrorStatus(data: Data, httpResponse: HTTPURLResponse) throws {
        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw LLMError.unauthorized
        case 429:
            throw LLMError.rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorResponse?.error.message ?? "Server error")
        default:
            throw LLMError.serverError(httpResponse.statusCode, "Unexpected status code")
        }
    }

    private func parseAgentError(data: Data, statusCode: Int) throws -> LLMError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 429:
            return .rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            return .invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            return .modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            return .serverError(statusCode, errorResponse?.error.message ?? "Server error")
        default:
            return .serverError(statusCode, "Unexpected status code")
        }
    }

    private func parseAgentSuccessResponse(data: Data) throws -> LLMResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let openAIResponse: OpenAICompatibleResponseBody
        do {
            openAIResponse = try decoder.decode(OpenAICompatibleResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return OpenAICompatibleResponseConverter.toLLMResponse(openAIResponse)
    }
}

// MARK: - Chat-specific Request Types

/// チャット専用リクエストボディ（簡易版: max_tokens を使用）
package struct OpenAICompatibleChatRequestBody: Encodable, Sendable {
    package let model: String
    package let messages: [OpenAICompatibleMessage]
    package let temperature: Double?
    package let maxTokens: Int?
    package let responseFormat: OpenAICompatibleChatResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let temperature = temperature {
            try container.encode(temperature, forKey: .temperature)
        }
        if let maxTokens = maxTokens {
            try container.encode(maxTokens, forKey: .maxTokens)
        }
        try container.encode(responseFormat, forKey: .responseFormat)
    }
}

/// チャット用レスポンスフォーマット
package struct OpenAICompatibleChatResponseFormat: Encodable, Sendable {
    package let type: String
    package let jsonSchema: OpenAICompatibleChatJSONSchema

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// チャット用 JSON スキーマ
package struct OpenAICompatibleChatJSONSchema: Encodable, @unchecked Sendable {
    package let name: String
    package let strict: Bool
    package let schema: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name, strict, schema
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(strict, forKey: .strict)
        let schemaData = try JSONSerialization.data(withJSONObject: schema)
        let schemaJSON = try JSONDecoder().decode(OpenAICompatibleJSONValue.self, from: schemaData)
        try container.encode(schemaJSON, forKey: .schema)
    }
}
