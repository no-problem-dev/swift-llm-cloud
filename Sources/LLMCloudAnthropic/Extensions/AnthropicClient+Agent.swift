import LLMCloudClient
import LLMClient
import LLMTool
import Foundation
import StructuredDataCore
import LLMClient
import LLMTool
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicClient + AgentCapableClient

extension AnthropicClient: AgentCapableClient {
    /// エージェントステップを実行
    ///
    /// Anthropic Claude API を使用してエージェントステップを実行します。
    /// ツールコールと構造化出力の両方をサポートします。
    /// リトライ設定に基づいて、レート制限やサーバーエラー時に自動リトライを行います。
    public func executeAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        _ = reasoningEffort
        _ = thinkingMode

        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0, includeThinking: true) }
        let anthropicTools = tools.isEmpty ? nil : try tools.toAnthropicFormat().map { try AnthropicToolDef(dict: $0) }
        let anthropicToolChoice: AnthropicToolChoiceValue? = tools.isEmpty
            ? nil
            : (toolChoice.map { AnthropicToolChoiceValue($0) } ?? .auto)
        let outputConfig = responseSchema.map {
            AnthropicOutputConfig(format: AnthropicOutputFormat(type: "json_schema", schema: $0))
        }

        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: nil,
            outputConfig: outputConfig,
            tools: anthropicTools,
            toolChoice: anthropicToolChoice
        )

        let beta = responseSchema != nil ? Self.structuredOutputsBeta : nil
        let response = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.baseProvider.sendBody(body, beta: beta).0
        }
        return Self.agentResponseToLLM(response)
    }

    private static func agentResponseToLLM(_ response: AnthropicResponseBody) -> LLMResponse {
        let contentBlocks: [LLMResponse.ContentBlock] = response.content.compactMap { block in
            switch block.type {
            case "text":
                return block.text.map { .text($0) }
            case "tool_use":
                guard let id = block.id, let name = block.name, let input = block.input,
                      let inputData = try? JSONEncoder().encode(input) else { return nil }
                return .toolUse(id: id, name: name, input: inputData)
            case "thinking":
                return block.text.map { .thinking(text: $0, signature: block.signature) }
            default:
                return nil
            }
        }
        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }
        )
    }

    // MARK: - Private Constants

    /// API バージョン
    private static let apiVersion = "2023-06-01"

    /// 構造化出力のベータヘッダー
    private static let structuredOutputsBeta = "structured-outputs-2025-11-13"

    /// デフォルトの最大トークン数（non-thinking 用）
    private static let defaultMaxTokens = 4096

    /// Extended Thinking 有効時のデフォルト最大トークン数
    private static let defaultMaxTokensWithThinking = 16384

    /// Extended Thinking 有効時のデフォルト思考バジェットトークン数
    ///
    /// `defaultMaxTokensWithThinking` (16384) のうち 10240 を思考に割り当て、
    /// 残り 6144 を出力用に確保します。
    private static let defaultThinkingBudgetTokens = 10240

    // MARK: - Private Helpers

    /// LLMMessage を Anthropic メッセージ形式に変換
    ///
    /// - Throws: `LLMError.mediaNotSupported` メディアコンテンツが含まれている場合
    private func convertToAnthropicMessage(_ message: LLMMessage) throws -> AnthropicAgentMessage {
        let role = message.role == .user ? "user" : "assistant"
        var contentBlocks: [AnthropicAgentMessageContent] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                contentBlocks.append(.text(text))
            case .toolUse(let id, let name, let input):
                contentBlocks.append(.toolUse(id: id, name: name, input: input))
            case .toolResult(let toolCallId, _, let resultContent):
                contentBlocks.append(.toolResult(toolUseId: toolCallId, content: resultContent.contentValue, isError: resultContent.isError))
            case .image(let imageContent):
                if case .base64(let data) = imageContent.source {
                    contentBlocks.append(.image(data: data, mediaType: imageContent.mimeType))
                }
            case .audio:
                throw LLMError.mediaNotSupported(mediaType: "audio", provider: "Anthropic Agent API")
            case .video:
                throw LLMError.mediaNotSupported(mediaType: "video", provider: "Anthropic Agent API")
            case .thinking(let text, let signature):
                contentBlocks.append(.thinking(text: text, signature: signature))
            }
        }

        return AnthropicAgentMessage(role: role, content: contentBlocks)
    }

    /// ToolChoice を Anthropic 形式に変換
    private func mapToolChoice(_ choice: ToolChoice) -> AnthropicAgentToolChoice {
        switch choice {
        case .auto:
            return .auto
        case .disabled:
            return .none
        case .required:
            return .any
        case .tool(let name):
            return .tool(name)
        }
    }

    /// エラーステータスコードから LLMError を生成
    private func parseAgentError(data: Data, statusCode: Int) throws -> LLMError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 429:
            return .rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(AnthropicAgentErrorResponse.self, from: data)
            return .invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(AnthropicAgentErrorResponse.self, from: data)
            return .modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(AnthropicAgentErrorResponse.self, from: data)
            return .serverError(statusCode, errorResponse?.error.message ?? "Server error")
        default:
            return .serverError(statusCode, "Unexpected status code")
        }
    }

    // MARK: - Streaming Agent Step

    /// エージェントステップをストリーミング実行
    ///
    /// thinking が有効な場合、SSE ストリーミングで thinking_delta/text_delta をリアルタイムに返します。
    /// thinking が無効な場合は既存の `executeAgentStep()` にフォールバックします。
    public func streamAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        _ = reasoningEffort // Anthropic 側では Extended Thinking が思考量制御の主役

        // 非対応モデル（Haiku 等）は自動で thinking 無効にフォールバック
        let effectiveThinkingMode: ThinkingMode
        if thinkingMode == .adaptive && !model.supportsExtendedThinking {
            effectiveThinkingMode = .disabled
        } else {
            effectiveThinkingMode = thinkingMode
        }

        // thinking 無効時はデフォルト実装（非ストリーミング）にフォールバック
        guard effectiveThinkingMode == .adaptive else {
            return makeCancellableStream { continuation in
                Task {
                    do {
                        let response = try await executeAgentStep(
                            messages: messages,
                            model: model,
                            systemPrompt: systemPrompt,
                            tools: tools,
                            toolChoice: toolChoice,
                            responseSchema: responseSchema,
                            thinkingMode: effectiveThinkingMode,
                            reasoningEffort: nil,
                            maxTokens: maxTokens
                        )
                        continuation.yield(.completed(response))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        return makeCancellableStream { continuation in
            Task {
                do {
                    try await self.executeStreamingAgentStep(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        toolChoice: toolChoice,
                        responseSchema: responseSchema,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// ストリーミングリクエストを実行
    private func executeStreamingAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?,
        continuation: AsyncThrowingStream<StreamingAgentEvent, Error>.Continuation
    ) async throws {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        // 構造化出力ベータヘッダー
        if responseSchema != nil {
            urlRequest.setValue(Self.structuredOutputsBeta, forHTTPHeaderField: "anthropic-beta")
        }

        // ストリーミング + thinking 付きリクエストボディ
        let body = try buildStreamingAgentRequestBody(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            maxTokens: maxTokens
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        // URLSession でストリーミング
        let (bytes, urlResponse) = try await session.bytes(for: urlRequest)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }

        guard httpResponse.statusCode == 200 else {
            // エラーレスポンスを収集
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let error = try parseAgentError(data: errorData, statusCode: httpResponse.statusCode)
            throw error
        }

        // SSE パースとデルタ配信
        var lineBuffer = DataLineBuffer()
        var sseParser = SSELineParser()
        var accumulator = AnthropicStreamAccumulator()

        for try await byte in bytes {
            let lines = lineBuffer.append(Data([byte]))
            for line in lines {
                if let event = sseParser.parseLine(line) {
                    let actions = accumulator.processEvent(event)
                    for action in actions {
                        switch action {
                        case .yieldDelta(let delta):
                            continuation.yield(.delta(delta))
                        case .yieldCompleted(let response):
                            continuation.yield(.completed(response))
                        case .error(let error):
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
            }
        }

        // ストリーム終了後にまだ完了イベントが来ていない場合
        if let response = accumulator.buildFinalResponse() {
            continuation.yield(.completed(response))
        }

        continuation.finish()
    }

    /// ストリーミング用リクエストボディを構築
    private func buildStreamingAgentRequestBody(
        model: ClaudeModel,
        messages: [LLMMessage],
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?
    ) throws -> AnthropicStreamingAgentRequestBody {
        let anthropicMessages = try messages.map { try convertToAnthropicMessage($0) }

        let anthropicTools: [[String: Any]]? = tools.isEmpty ? nil : tools.toAnthropicFormat()
        let anthropicToolChoice: AnthropicAgentToolChoice? = tools.isEmpty ? nil : (toolChoice.map { mapToolChoice($0) } ?? .auto)

        var outputFormat: AnthropicAgentOutputFormat?
        if let schema = responseSchema {
            outputFormat = AnthropicAgentOutputFormat(
                type: "json_schema",
                schema: schema
            )
        }

        let effectiveMaxTokens = maxTokens ?? Self.defaultMaxTokensWithThinking
        let effectiveBudget = min(Self.defaultThinkingBudgetTokens, effectiveMaxTokens - 1)

        return AnthropicStreamingAgentRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: effectiveMaxTokens,
            tools: anthropicTools,
            toolChoice: anthropicToolChoice,
            outputConfig: outputFormat.map { AnthropicAgentOutputConfig(format: $0) },
            stream: true,
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: effectiveBudget)
        )
    }
}

// MARK: - AnthropicStreamAccumulator

/// SSE イベントからストリーミングデルタと完全レスポンスを生成するアキュムレータ
private struct AnthropicStreamAccumulator {
    enum Action {
        case yieldDelta(StreamDelta)
        case yieldCompleted(LLMResponse)
        case error(LLMError)
    }

    private var thinkingTexts: [(text: String, signature: String?)] = []
    private var currentThinkingText = ""
    private var currentThinkingSignature: String?
    private var textContent = ""
    private var toolUseBlocks: [(id: String, name: String, inputJSON: String)] = []
    private var currentToolId: String?
    private var currentToolName: String?
    private var currentToolInput = ""
    private var model = ""
    private var inputTokens = 0
    private var outputTokens = 0
    private var cacheCreationTokens: Int?
    private var cacheReadTokens: Int?
    private var stopReason: String?
    private var completed = false

    mutating func processEvent(_ event: SSEParsedEvent) -> [Action] {
        guard let eventType = event.event else { return [] }

        switch eventType {
        case "message_start":
            return processMessageStart(event.data)
        case "content_block_start":
            return processContentBlockStart(event.data)
        case "content_block_delta":
            return processContentBlockDelta(event.data)
        case "content_block_stop":
            return processContentBlockStop()
        case "message_delta":
            return processMessageDelta(event.data)
        case "message_stop":
            return processMessageStop()
        case "error":
            return processError(event.data)
        default:
            return []
        }
    }

    /// ストリーム終了後にまだレスポンスが返されていない場合に最終レスポンスを構築
    func buildFinalResponse() -> LLMResponse? {
        guard !completed else { return nil }
        return buildResponse()
    }

    // MARK: - Private Event Handlers

    private mutating func processMessageStart(_ data: String) -> [Action] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let message = json["message"] as? [String: Any] else { return [] }

        model = message["model"] as? String ?? ""
        if let usage = message["usage"] as? [String: Any] {
            inputTokens = usage["input_tokens"] as? Int ?? 0
            outputTokens = usage["output_tokens"] as? Int ?? 0
            cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int
            cacheReadTokens = usage["cache_read_input_tokens"] as? Int
        }
        return []
    }

    private mutating func processContentBlockStart(_ data: String) -> [Action] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let contentBlock = json["content_block"] as? [String: Any],
              let type = contentBlock["type"] as? String else { return [] }

        switch type {
        case "thinking":
            currentThinkingText = ""
            currentThinkingSignature = nil
        case "text":
            break
        case "tool_use":
            currentToolId = contentBlock["id"] as? String
            currentToolName = contentBlock["name"] as? String
            currentToolInput = ""
        default:
            break
        }
        return []
    }

    private mutating func processContentBlockDelta(_ data: String) -> [Action] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let delta = json["delta"] as? [String: Any],
              let type = delta["type"] as? String else { return [] }

        switch type {
        case "thinking_delta":
            if let thinking = delta["thinking"] as? String {
                currentThinkingText += thinking
                return [.yieldDelta(.thinkingDelta(thinking))]
            }
        case "signature_delta":
            if let signature = delta["signature"] as? String {
                currentThinkingSignature = (currentThinkingSignature ?? "") + signature
            }
        case "text_delta":
            if let text = delta["text"] as? String {
                textContent += text
                return [.yieldDelta(.textDelta(text))]
            }
        case "input_json_delta":
            if let partialJson = delta["partial_json"] as? String {
                currentToolInput += partialJson
            }
        default:
            break
        }
        return []
    }

    private mutating func processContentBlockStop() -> [Action] {
        // thinking ブロック完了
        if !currentThinkingText.isEmpty {
            thinkingTexts.append((text: currentThinkingText, signature: currentThinkingSignature))
            currentThinkingText = ""
            currentThinkingSignature = nil
        }

        // tool_use ブロック完了
        if let id = currentToolId, let name = currentToolName {
            toolUseBlocks.append((id: id, name: name, inputJSON: currentToolInput))
            currentToolId = nil
            currentToolName = nil
            currentToolInput = ""
        }

        return []
    }

    private mutating func processMessageDelta(_ data: String) -> [Action] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let delta = json["delta"] as? [String: Any] else { return [] }

        stopReason = delta["stop_reason"] as? String

        if let usage = json["usage"] as? [String: Any] {
            outputTokens = usage["output_tokens"] as? Int ?? outputTokens
        }
        return []
    }

    private mutating func processMessageStop() -> [Action] {
        completed = true
        if let response = buildResponse() {
            return [.yieldCompleted(response)]
        }
        return []
    }

    private mutating func processError(_ data: String) -> [Action] {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return [.error(.serverError(0, "Unknown streaming error"))]
        }

        let message = error["message"] as? String ?? "Unknown error"
        return [.error(.serverError(0, message))]
    }

    // MARK: - Response Building

    private func buildResponse() -> LLMResponse? {
        var contentBlocks: [LLMResponse.ContentBlock] = []

        // thinking ブロック
        for thinking in thinkingTexts {
            contentBlocks.append(.thinking(text: thinking.text, signature: thinking.signature))
        }

        // テキストブロック
        if !textContent.isEmpty {
            contentBlocks.append(.text(textContent))
        }

        // tool_use ブロック
        for tool in toolUseBlocks {
            let inputData = tool.inputJSON.data(using: .utf8) ?? Data()
            contentBlocks.append(.toolUse(id: tool.id, name: tool.name, input: inputData))
        }

        guard !contentBlocks.isEmpty else { return nil }

        let parsedStopReason = stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        return LLMResponse(
            content: contentBlocks,
            model: model,
            usage: AnthropicUsageNormalizer.normalize(
                rawInputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            stopReason: parsedStopReason
        )
    }
}

// MARK: - Streaming Request Body

/// ストリーミング用 Anthropic リクエストボディ
private struct AnthropicStreamingAgentRequestBody: Encodable {
    let model: String
    let messages: [AnthropicAgentMessage]
    let system: String?
    let maxTokens: Int
    let tools: [[String: Any]]?
    let toolChoice: AnthropicAgentToolChoice?
    let outputConfig: AnthropicAgentOutputConfig?
    let stream: Bool
    let thinking: AnthropicThinkingConfig

    enum CodingKeys: String, CodingKey {
        case model, messages, system, tools, stream, thinking
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case outputConfig = "output_config"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let system = system {
            try container.encode(system, forKey: .system)
        }
        try container.encode(maxTokens, forKey: .maxTokens)
        // temperature は thinking 有効時には指定不可（API 制約）

        if let tools = tools {
            let toolDefs = tools.map { AnthropicAgentToolDef(dict: $0) }
            try container.encode(toolDefs, forKey: .tools)
        }
        if let toolChoice = toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        if let outputConfig = outputConfig {
            try container.encode(outputConfig, forKey: .outputConfig)
        }
        try container.encode(stream, forKey: .stream)
        try container.encode(thinking, forKey: .thinking)
    }
}

/// Anthropic thinking 設定
private struct AnthropicThinkingConfig: Encodable {
    let type: String
    let budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

// MARK: - Anthropic Agent Streaming Types

/// Anthropic ツール定義
private struct AnthropicAgentToolDef: Encodable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    init(dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        self.inputSchema = dict["input_schema"] as? [String: Any] ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        let schemaData = try JSONSerialization.data(withJSONObject: inputSchema)
        let schemaJSON = try JSONDecoder().decode(AgentJSONValue.self, from: schemaData)
        try container.encode(schemaJSON, forKey: .inputSchema)
    }
}

/// Anthropic ツール選択値
private enum AnthropicAgentToolChoice: Encodable {
    case auto
    case any
    case none
    case tool(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode(["type": "auto"])
        case .any:
            try container.encode(["type": "any"])
        case .none:
            try container.encode(["type": "auto"])
        case .tool(let name):
            try container.encode(["type": "tool", "name": name])
        }
    }
}

/// Anthropic 出力フォーマット設定
private struct AnthropicAgentOutputFormat: Encodable {
    let type: String
    let schema: JSONSchema
}

/// Anthropic エージェント出力設定
private struct AnthropicAgentOutputConfig: Encodable {
    let format: AnthropicAgentOutputFormat?
}

/// Anthropic メッセージ
private struct AnthropicAgentMessage: Encodable {
    let role: String
    let content: [AnthropicAgentMessageContent]
}

/// Anthropic メッセージコンテンツ
private enum AnthropicAgentMessageContent: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: Data)
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case thinking(text: String, signature: String?)
    case image(data: Data, mediaType: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .text(let text):
            try container.encode(["type": "text", "text": text])

        case .toolUse(let id, let name, let input):
            let inputDict: [String: Any]
            if let dict = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
                inputDict = dict
            } else {
                inputDict = [:]
            }
            let inputData = try JSONSerialization.data(withJSONObject: inputDict)
            let inputJSON = try JSONDecoder().decode(AgentJSONValue.self, from: inputData)

            let dict: [String: AgentJSONValue] = [
                "type": .string("tool_use"),
                "id": .string(id),
                "name": .string(name),
                "input": inputJSON
            ]
            try container.encode(dict)

        case .toolResult(let toolUseId, let resultContent, let isError):
            var dict: [String: AgentJSONValue] = [
                "type": .string("tool_result"),
                "tool_use_id": .string(toolUseId),
                "content": .string(resultContent)
            ]
            if isError {
                dict["is_error"] = .bool(true)
            }
            try container.encode(dict)

        case .thinking(let text, let signature):
            var dict: [String: AgentJSONValue] = [
                "type": .string("thinking"),
                "thinking": .string(text)
            ]
            if let signature {
                dict["signature"] = .string(signature)
            }
            try container.encode(dict)

        case .image(let data, let mediaType):
            let dict: [String: AgentJSONValue] = [
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"),
                    "media_type": .string(mediaType),
                    "data": .string(data.base64EncodedString())
                ])
            ]
            try container.encode(dict)
        }
    }
}

/// JSON 値の汎用エンコード/デコード用
private typealias AgentJSONValue = StructuredValue

/// Anthropic エラーレスポンス
private struct AnthropicAgentErrorResponse: Decodable {
    let type: String
    let error: AnthropicAgentError
}

/// Anthropic エラー詳細
private struct AnthropicAgentError: Decodable {
    let type: String
    let message: String
}
