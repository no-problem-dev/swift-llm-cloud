import LLMCloudClient
import LLMClient
import LLMTool
import Foundation
import StructuredDataCore
import LLMClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicClient + ToolCallableClient

extension AnthropicClient: ToolCallableClient {
    /// ツール呼び出しを計画する（会話履歴付き）
    ///
    /// Anthropic Claude API を使用してツール呼び出しを計画します。
    public func planToolCalls(
        messages: [LLMMessage],
        model: ClaudeModel,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        // HTTPリクエストを構築
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        // リクエストボディを構築
        let body = try buildToolRequestBody(
            model: model,
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        // リクエストを送信
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidRequest("Invalid response type")
        }

        // レスポンスを処理
        return try handleToolResponse(data: data, httpResponse: httpResponse)
    }

    // MARK: - Private Constants

    /// API バージョン
    private static let apiVersion = "2023-06-01"

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Private Helpers

    /// ツールリクエストボディを構築
    ///
    /// - Throws: `LLMError.mediaNotSupported` メディアコンテンツが含まれている場合
    private func buildToolRequestBody(
        model: ClaudeModel,
        messages: [LLMMessage],
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) throws -> AnthropicToolRequestBody {
        let anthropicMessages = try messages.map { try convertToAnthropicMessage($0) }
        let anthropicTools = tools.toAnthropicFormat()
        let anthropicToolChoice = toolChoice.map { mapToolChoice($0) }

        return AnthropicToolRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: temperature,
            tools: anthropicTools,
            toolChoice: anthropicToolChoice
        )
    }

    /// LLMMessage を Anthropic メッセージ形式に変換
    ///
    /// - Throws: `LLMError.mediaNotSupported` メディアコンテンツが含まれている場合
    private func convertToAnthropicMessage(_ message: LLMMessage) throws -> AnthropicToolMessage {
        let role = message.role == .user ? "user" : "assistant"
        var contentBlocks: [AnthropicToolMessageContent] = []

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
                throw LLMError.mediaNotSupported(mediaType: "audio", provider: "Anthropic Tool API")
            case .video:
                throw LLMError.mediaNotSupported(mediaType: "video", provider: "Anthropic Tool API")
            case .thinking:
                break // Tool API では thinking は無視
            }
        }

        return AnthropicToolMessage(role: role, content: contentBlocks)
    }

    /// ToolChoice を Anthropic 形式に変換
    private func mapToolChoice(_ choice: ToolChoice) -> AnthropicToolChoiceValue {
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

    /// レスポンスを処理
    private func handleToolResponse(data: Data, httpResponse: HTTPURLResponse) throws -> ToolCallResponse {
        // エラーステータスコードの処理
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw LLMError.unauthorized
        case 429:
            throw LLMError.rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(AnthropicToolErrorResponse.self, from: data)
            throw LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(AnthropicToolErrorResponse.self, from: data)
            throw LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(AnthropicToolErrorResponse.self, from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorResponse?.error.message ?? "Server error")
        default:
            throw LLMError.serverError(httpResponse.statusCode, "Unexpected status code")
        }

        // 成功レスポンスをデコード
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let anthropicResponse: AnthropicToolResponseBody
        do {
            anthropicResponse = try decoder.decode(AnthropicToolResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        // ToolCallResponse に変換
        return parseToolCallResponse(anthropicResponse)
    }

    /// Anthropic レスポンスから ToolCallResponse を生成
    private func parseToolCallResponse(_ response: AnthropicToolResponseBody) -> ToolCallResponse {
        var toolCalls: [ToolCall] = []
        var textContent: String?

        for block in response.content {
            switch block.type {
            case "text":
                textContent = block.text
            case "tool_use":
                if let id = block.id, let name = block.name, let input = block.input {
                    if let inputData = try? JSONSerialization.data(withJSONObject: input) {
                        toolCalls.append(ToolCall(id: id, name: name, arguments: inputData))
                    }
                }
            default:
                break
            }
        }

        let stopReason: LLMResponse.StopReason? = response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        return ToolCallResponse(
            toolCalls: toolCalls,
            text: textContent,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: stopReason,
            model: response.model
        )
    }
}

// MARK: - Anthropic Tool Request/Response Types

/// Anthropic ツールリクエストボディ
private struct AnthropicToolRequestBody: Encodable {
    let model: String
    let messages: [AnthropicToolMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let tools: [[String: Any]]
    let toolChoice: AnthropicToolChoiceValue?

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let system = system {
            try container.encode(system, forKey: .system)
        }
        try container.encode(maxTokens, forKey: .maxTokens)
        if let temperature = temperature {
            try container.encode(temperature, forKey: .temperature)
        }

        // tools を直接エンコード
        let toolDefs = tools.map { AnthropicToolDef(dict: $0) }
        try container.encode(toolDefs, forKey: .tools)

        if let toolChoice = toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
    }
}

/// Anthropic ツール定義
private struct AnthropicToolDef: Encodable {
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
        let schemaJSON = try JSONDecoder().decode(JSONValue.self, from: schemaData)
        try container.encode(schemaJSON, forKey: .inputSchema)
    }
}

/// Anthropic ツール選択値
private enum AnthropicToolChoiceValue: Encodable {
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

/// Anthropic メッセージ
private struct AnthropicToolMessage: Encodable {
    let role: String
    let content: [AnthropicToolMessageContent]
}

/// Anthropic メッセージコンテンツ
private enum AnthropicToolMessageContent: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: Data)
    case toolResult(toolUseId: String, content: String, isError: Bool)
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
            let inputJSON = try JSONDecoder().decode(JSONValue.self, from: inputData)

            let dict: [String: JSONValue] = [
                "type": .string("tool_use"),
                "id": .string(id),
                "name": .string(name),
                "input": inputJSON
            ]
            try container.encode(dict)

        case .toolResult(let toolUseId, let resultContent, let isError):
            var dict: [String: JSONValue] = [
                "type": .string("tool_result"),
                "tool_use_id": .string(toolUseId),
                "content": .string(resultContent)
            ]
            if isError {
                dict["is_error"] = .bool(true)
            }
            try container.encode(dict)

        case .image(let data, let mediaType):
            let dict: [String: JSONValue] = [
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

// JSONValue は Contract/AnthropicTypes.swift で定義済み

/// Anthropic ツールレスポンスボディ
private struct AnthropicToolResponseBody: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicToolContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicToolUsage
}

/// Anthropic コンテンツブロック
private struct AnthropicToolContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        if let inputData = try? container.decodeIfPresent(AnyCodable.self, forKey: .input) {
            input = inputData.anyValue as? [String: Any]
        } else {
            input = nil
        }
    }
}

// AnyCodable は Contract/AnthropicTypes.swift で定義済み

/// Anthropic 使用量
private struct AnthropicToolUsage: Decodable, AnthropicUsageRaw {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

/// Anthropic エラーレスポンス
private struct AnthropicToolErrorResponse: Decodable {
    let type: String
    let error: AnthropicToolError
}

/// Anthropic エラー詳細
private struct AnthropicToolError: Decodable {
    let type: String
    let message: String
}
