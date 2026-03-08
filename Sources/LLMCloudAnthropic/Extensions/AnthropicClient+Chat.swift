import LLMCloudClient
import LLMClient
import LLMChat
import Foundation
import LLMClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicClient + ChatCapableClient

extension AnthropicClient: ChatCapableClient {
    /// 会話を継続し、構造化出力と会話履歴情報を取得
    ///
    /// Anthropic Claude API を使用して会話を継続します。
    public func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        // HTTPリクエストを構築
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(Self.structuredOutputsBeta, forHTTPHeaderField: "anthropic-beta")

        // スキーマ情報を含むシステムプロンプトを構築
        let enhancedSystemPrompt = buildSystemPrompt(
            base: systemPrompt,
            schema: T.jsonSchema
        )

        // リクエストボディを構築
        let body = try buildChatRequestBody(
            model: model,
            messages: messages,
            systemPrompt: enhancedSystemPrompt,
            responseSchema: T.jsonSchema,
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
        return try handleChatResponse(data: data, httpResponse: httpResponse)
    }

    // MARK: - Private Constants

    /// API バージョン
    private static let apiVersion = "2023-06-01"

    /// 構造化出力のベータヘッダー
    private static let structuredOutputsBeta = "structured-outputs-2025-11-13"

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Private Helpers

    /// システムプロンプトにスキーマ情報を付加
    private func buildSystemPrompt(base: String?, schema: JSONSchema) -> String {
        var parts: [String] = []

        if let base = base {
            parts.append(base)
        }

        // スキーマの説明を追加
        if let description = schema.description {
            parts.append("出力形式: \(description)")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    /// チャットリクエストボディを構築
    ///
    /// - Throws: `LLMError.mediaNotSupported` メディアコンテンツが含まれている場合
    private func buildChatRequestBody(
        model: ClaudeModel,
        messages: [LLMMessage],
        systemPrompt: String?,
        responseSchema: JSONSchema,
        temperature: Double?,
        maxTokens: Int?
    ) throws -> AnthropicChatRequestBody {
        let anthropicMessages = try messages.map { try convertToAnthropicMessage($0) }

        let adapter = AnthropicSchemaAdapter()
        let outputFormat = AnthropicChatOutputFormat(
            type: "json_schema",
            schema: adapter.adapt(responseSchema)
        )

        return AnthropicChatRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt,
            maxTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: temperature,
            outputConfig: AnthropicChatOutputConfig(format: outputFormat)
        )
    }

    /// LLMMessage を Anthropic メッセージ形式に変換
    ///
    /// - Throws: `LLMError.mediaNotSupported` メディアコンテンツが含まれている場合
    private func convertToAnthropicMessage(_ message: LLMMessage) throws -> AnthropicChatMessage {
        let role = message.role == .user ? "user" : "assistant"
        var contentBlocks: [AnthropicChatMessageContent] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                contentBlocks.append(.text(text))
            case .toolUse(let id, let name, let input):
                contentBlocks.append(.toolUse(id: id, name: name, input: input))
            case .toolResult(let toolCallId, _, let resultContent, let isError):
                contentBlocks.append(.toolResult(toolUseId: toolCallId, content: resultContent, isError: isError))
            case .image:
                // Chat APIではメディアコンテンツは現在サポートされていません
                throw LLMError.mediaNotSupported(mediaType: "image", provider: "Anthropic Chat API")
            case .audio:
                throw LLMError.mediaNotSupported(mediaType: "audio", provider: "Anthropic Chat API")
            case .video:
                throw LLMError.mediaNotSupported(mediaType: "video", provider: "Anthropic Chat API")
            case .thinking:
                break // Chat API では thinking は無視
            }
        }

        return AnthropicChatMessage(role: role, content: contentBlocks)
    }

    /// レスポンスを処理
    private func handleChatResponse<T: StructuredProtocol>(
        data: Data,
        httpResponse: HTTPURLResponse
    ) throws -> ChatResponse<T> {
        // エラーステータスコードの処理
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw LLMError.unauthorized
        case 429:
            throw LLMError.rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(AnthropicChatErrorResponse.self, from: data)
            throw LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(AnthropicChatErrorResponse.self, from: data)
            throw LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(AnthropicChatErrorResponse.self, from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorResponse?.error.message ?? "Server error")
        default:
            throw LLMError.serverError(httpResponse.statusCode, "Unexpected status code")
        }

        // 成功レスポンスをデコード
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let anthropicResponse: AnthropicChatResponseBody
        do {
            anthropicResponse = try decoder.decode(AnthropicChatResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        // テキストコンテンツを取得
        guard let rawText = anthropicResponse.content.first(where: { $0.type == "text" })?.text else {
            throw LLMError.emptyResponse
        }

        // 構造化出力をデコード
        guard let jsonData = rawText.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let resultDecoder = JSONDecoder()
        resultDecoder.keyDecodingStrategy = .convertFromSnakeCase

        let result: T
        do {
            result = try resultDecoder.decode(T.self, from: jsonData)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        let stopReason = anthropicResponse.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        return ChatResponse(
            result: result,
            assistantMessage: .assistant(rawText),
            usage: TokenUsage(
                inputTokens: anthropicResponse.usage.inputTokens,
                outputTokens: anthropicResponse.usage.outputTokens,
                cacheCreationTokens: anthropicResponse.usage.cacheCreationInputTokens,
                cacheReadTokens: anthropicResponse.usage.cacheReadInputTokens
            ),
            stopReason: stopReason,
            model: anthropicResponse.model,
            rawText: rawText
        )
    }
}

// MARK: - Anthropic Chat Request/Response Types

/// Anthropic チャットリクエストボディ
private struct AnthropicChatRequestBody: Encodable {
    let model: String
    let messages: [AnthropicChatMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let outputConfig: AnthropicChatOutputConfig

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let system = system, !system.isEmpty {
            try container.encode(system, forKey: .system)
        }
        try container.encode(maxTokens, forKey: .maxTokens)
        if let temperature = temperature {
            try container.encode(temperature, forKey: .temperature)
        }
        try container.encode(outputConfig, forKey: .outputConfig)
    }
}

/// Anthropic メッセージ
private struct AnthropicChatMessage: Encodable {
    let role: String
    let content: [AnthropicChatMessageContent]
}

/// Anthropic メッセージコンテンツ
private enum AnthropicChatMessageContent: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: Data)
    case toolResult(toolUseId: String, content: String, isError: Bool)

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
        }
    }
}

/// Anthropic 出力フォーマット設定
private struct AnthropicChatOutputFormat: Encodable {
    let type: String
    let schema: JSONSchema
}

/// Anthropic チャット出力設定
private struct AnthropicChatOutputConfig: Encodable {
    let format: AnthropicChatOutputFormat?
}

// JSONValue は Contract/AnthropicTypes.swift で定義済み

/// Anthropic チャットレスポンスボディ
private struct AnthropicChatResponseBody: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicChatContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicChatUsage
}

/// Anthropic コンテンツブロック
private struct AnthropicChatContentBlock: Decodable {
    let type: String
    let text: String?
}

/// Anthropic 使用量
private struct AnthropicChatUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

/// Anthropic エラーレスポンス
private struct AnthropicChatErrorResponse: Decodable {
    let type: String
    let error: AnthropicChatError
}

/// Anthropic エラー詳細
private struct AnthropicChatError: Decodable {
    let type: String
    let message: String
}
