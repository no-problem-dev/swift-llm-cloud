import LLMCloudClient
import LLMClient
import LLMTool
import Foundation
import LLMClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient + ToolCallableClient

extension GeminiClient: ToolCallableClient {
    /// ツール呼び出しを計画する（会話履歴付き）
    ///
    /// Google Gemini API を使用してツール呼び出しを計画します。
    public func planToolCalls(
        messages: [LLMMessage],
        model: GeminiModel,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        // エンドポイントを構築
        let endpoint = URL(string: "\(baseURL)/\(model.id):generateContent?key=\(apiKey)")!

        // HTTPリクエストを構築
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // リクエストボディを構築
        let body = buildToolRequestBody(
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
        return try handleToolResponse(data: data, httpResponse: httpResponse, model: model.id)
    }

    // MARK: - Private Constants

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Private Helpers

    /// ツールリクエストボディを構築
    private func buildToolRequestBody(
        model: GeminiModel,
        messages: [LLMMessage],
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) -> GeminiToolRequestBody {
        // コンテンツを構築
        var contents: [GeminiToolContent] = []

        for message in messages {
            contents.append(contentsOf: convertToGeminiContents(message))
        }

        // システムインストラクション
        var systemInstruction: GeminiToolContent?
        if let prompt = systemPrompt {
            systemInstruction = GeminiToolContent(
                role: "user",
                parts: [GeminiToolPart(text: prompt.render())]
            )
        }

        // 生成設定
        let generationConfig = GeminiToolGenerationConfig(
            maxOutputTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: temperature
        )

        // ツール設定
        let geminiTools: [GeminiToolDef]?
        let toolConfig: GeminiToolToolConfig?

        if !tools.isEmpty {
            let functionDeclarations = tools.toGeminiFormat().map { GeminiToolFunctionDeclaration(dict: $0) }
            geminiTools = [GeminiToolDef(functionDeclarations: functionDeclarations)]
            toolConfig = toolChoice.map { mapToolChoice($0, tools: tools) }
        } else {
            geminiTools = nil
            toolConfig = nil
        }

        return GeminiToolRequestBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            tools: geminiTools,
            toolConfig: toolConfig
        )
    }

    /// LLMMessage を Gemini コンテンツ形式に変換
    private func convertToGeminiContents(_ message: LLMMessage) -> [GeminiToolContent] {
        let role = message.role == .user ? "user" : "model"
        var parts: [GeminiToolPart] = []
        var toolResultParts: [GeminiToolPart] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                parts.append(GeminiToolPart(text: text))

            case .toolUse(let id, let name, let input):
                // ツール呼び出し（モデルからの応答）
                let args: [String: Any]?
                if let argsDict = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
                    args = argsDict
                } else {
                    args = nil
                }
                let functionCall = GeminiToolFunctionCall(name: name, args: args)
                let sig = GeminiThoughtSignatureEncoding.decodeThoughtSignature(from: id)
                parts.append(GeminiToolPart(functionCall: functionCall, thoughtSignature: sig))

            case .toolResult(_, let name, let content):
                // ツール結果（ユーザーからの応答）
                let responseDict: [String: Any] = ["result": content.contentValue]
                let functionResponse = GeminiToolFunctionResponse(name: name, response: responseDict)
                toolResultParts.append(GeminiToolPart(functionResponse: functionResponse))

            case .image(let imageContent):
                if let part = convertMediaToToolPart(source: imageContent.source, mimeType: imageContent.mediaType) {
                    parts.append(part)
                }
            case .audio(let audioContent):
                if let part = convertMediaToToolPart(source: audioContent.source, mimeType: audioContent.mediaType) {
                    parts.append(part)
                }
            case .video(let videoContent):
                if let part = convertMediaToToolPart(source: videoContent.source, mimeType: videoContent.mediaType) {
                    parts.append(part)
                }
            case .thinking:
                break // Gemini では thinking は無視
            }
        }

        var contents: [GeminiToolContent] = []

        // 通常のパーツ（テキストとツール呼び出し）
        if !parts.isEmpty {
            contents.append(GeminiToolContent(role: role, parts: parts))
        }

        // ツール結果は常にuserロールで送信
        if !toolResultParts.isEmpty {
            contents.append(GeminiToolContent(role: "user", parts: toolResultParts))
        }

        return contents
    }

    /// ToolChoice を Gemini 形式に変換
    private func mapToolChoice(_ choice: ToolChoice, tools: ToolSet) -> GeminiToolToolConfig {
        let config: GeminiToolFunctionCallingConfig
        switch choice {
        case .auto:
            config = GeminiToolFunctionCallingConfig(mode: "AUTO", allowedFunctionNames: nil)
        case .disabled:
            config = GeminiToolFunctionCallingConfig(mode: "NONE", allowedFunctionNames: nil)
        case .required:
            config = GeminiToolFunctionCallingConfig(mode: "ANY", allowedFunctionNames: nil)
        case .tool(let name):
            config = GeminiToolFunctionCallingConfig(mode: "ANY", allowedFunctionNames: [name])
        }
        return GeminiToolToolConfig(functionCallingConfig: config)
    }

    /// メディアソースを Tool API パーツに変換
    private func convertMediaToToolPart<T: MediaType>(source: MediaSource, mimeType: T) -> GeminiToolPart? {
        switch source {
        case .base64(let data):
            let base64String = data.base64EncodedString()
            let inlineData = GeminiToolInlineData(mimeType: mimeType.mimeType, data: base64String)
            return GeminiToolPart(inlineData: inlineData)
        case .url(let url):
            let fileData = GeminiToolFileData(mimeType: mimeType.mimeType, fileUri: url.absoluteString)
            return GeminiToolPart(fileData: fileData)
        case .fileReference(let id):
            let fileData = GeminiToolFileData(mimeType: mimeType.mimeType, fileUri: id)
            return GeminiToolPart(fileData: fileData)
        }
    }

    /// レスポンスを処理
    private func handleToolResponse(data: Data, httpResponse: HTTPURLResponse, model: String) throws -> ToolCallResponse {
        // エラーステータスコードの処理
        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw LLMError.unauthorized
        case 429:
            throw LLMError.rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(GeminiToolErrorResponse.self, from: data)
            throw LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(GeminiToolErrorResponse.self, from: data)
            throw LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(GeminiToolErrorResponse.self, from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorResponse?.error.message ?? "Server error")
        default:
            throw LLMError.serverError(httpResponse.statusCode, "Unexpected status code")
        }

        // 成功レスポンスをデコード
        let decoder = JSONDecoder()

        let geminiResponse: GeminiToolResponseBody
        do {
            geminiResponse = try decoder.decode(GeminiToolResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        // ToolCallResponse に変換
        return parseToolCallResponse(geminiResponse, model: model)
    }

    /// Gemini レスポンスから ToolCallResponse を生成
    private func parseToolCallResponse(_ response: GeminiToolResponseBody, model: String) -> ToolCallResponse {
        var toolCalls: [ToolCall] = []
        var textContent: String?

        // 最初の候補を取得
        guard let candidate = response.candidates?.first,
              let content = candidate.content else {
            // 使用量を取得
            let usage: TokenUsage
            if let usageMetadata = response.usageMetadata {
                usage = TokenUsage(
                    inputTokens: usageMetadata.promptTokenCount ?? 0,
                    outputTokens: usageMetadata.candidatesTokenCount ?? 0,
                    cacheReadTokens: usageMetadata.cachedContentTokenCount,
                    reasoningTokens: usageMetadata.thoughtsTokenCount
                )
            } else {
                usage = TokenUsage(inputTokens: 0, outputTokens: 0)
            }
            return ToolCallResponse(
                toolCalls: [],
                text: nil,
                usage: usage,
                stopReason: nil,
                model: model
            )
        }

        // パーツを処理
        for part in content.parts {
            // テキストコンテンツ
            if let text = part.text {
                textContent = text
            }
            // 関数呼び出し
            if let functionCall = part.functionCall {
                if let argsData = try? JSONSerialization.data(withJSONObject: functionCall.args ?? [:]) {
                    toolCalls.append(ToolCall(
                        id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                        name: functionCall.name,
                        arguments: argsData
                    ))
                }
            }
        }

        // 停止理由をマッピング
        let stopReason = mapStopReason(candidate.finishReason)

        // 使用量を取得
        let usage: TokenUsage
        if let usageMetadata = response.usageMetadata {
            usage = TokenUsage(
                inputTokens: usageMetadata.promptTokenCount ?? 0,
                outputTokens: usageMetadata.candidatesTokenCount ?? 0,
                cacheReadTokens: usageMetadata.cachedContentTokenCount,
                reasoningTokens: usageMetadata.thoughtsTokenCount
            )
        } else {
            usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        }

        return ToolCallResponse(
            toolCalls: toolCalls,
            text: textContent,
            usage: usage,
            stopReason: stopReason,
            model: model
        )
    }

    /// 停止理由をマッピング
    private func mapStopReason(_ reason: String?) -> LLMResponse.StopReason? {
        guard let reason = reason else { return nil }
        switch reason {
        case "STOP":
            return .endTurn
        case "MAX_TOKENS":
            return .maxTokens
        case "SAFETY":
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Gemini Tool Request/Response Types

/// Gemini ツールリクエストボディ
private struct GeminiToolRequestBody: Encodable {
    let contents: [GeminiToolContent]
    let systemInstruction: GeminiToolContent?
    let generationConfig: GeminiToolGenerationConfig
    let tools: [GeminiToolDef]?
    let toolConfig: GeminiToolToolConfig?
}

/// Gemini ツール定義
private struct GeminiToolDef: Encodable {
    let functionDeclarations: [GeminiToolFunctionDeclaration]
}

/// Gemini 関数宣言
private struct GeminiToolFunctionDeclaration: Encodable {
    let name: String
    let description: String
    let parameters: [String: Any]

    init(dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        self.parameters = dict["parameters"] as? [String: Any] ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        let paramsData = try JSONSerialization.data(withJSONObject: parameters)
        let paramsJSON = try JSONDecoder().decode(GeminiToolJSONValue.self, from: paramsData)
        try container.encode(paramsJSON, forKey: .parameters)
    }
}

/// Gemini ツール設定
private struct GeminiToolToolConfig: Encodable {
    let functionCallingConfig: GeminiToolFunctionCallingConfig
}

/// Gemini 関数呼び出し設定
private struct GeminiToolFunctionCallingConfig: Encodable {
    let mode: String
    let allowedFunctionNames: [String]?
}

/// Gemini コンテンツ
private struct GeminiToolContent: Codable {
    let role: String?
    let parts: [GeminiToolPart]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        // Gemini が空レスポンス（ツール呼び出し後に停止等）を返す場合、
        // parts キーが省略されることがある。その場合は空配列として扱う。
        parts = (try? container.decodeIfPresent([GeminiToolPart].self, forKey: .parts)) ?? []
    }

    init(role: String?, parts: [GeminiToolPart]) {
        self.role = role
        self.parts = parts
    }
}

/// Gemini パーツ
private struct GeminiToolPart: Codable {
    let text: String?
    let functionCall: GeminiToolFunctionCall?
    let functionResponse: GeminiToolFunctionResponse?
    let inlineData: GeminiToolInlineData?
    let fileData: GeminiToolFileData?
    let thoughtSignature: String?

    init(text: String) {
        self.text = text
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiToolFunctionCall) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiToolFunctionCall, thoughtSignature: String?) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = thoughtSignature
    }

    init(functionResponse: GeminiToolFunctionResponse) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = functionResponse
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(inlineData: GeminiToolInlineData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = inlineData
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(fileData: GeminiToolFileData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = fileData
        self.thoughtSignature = nil
    }
}

/// Gemini インラインデータ（Base64エンコードされたメディア）
private struct GeminiToolInlineData: Codable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

/// Gemini ファイルデータ（URL/ファイル参照）
private struct GeminiToolFileData: Codable {
    let mimeType: String
    let fileUri: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case fileUri = "file_uri"
    }
}

/// Gemini 関数呼び出し
private struct GeminiToolFunctionCall: Codable {
    let name: String
    let args: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case name, args
    }

    init(name: String, args: [String: Any]?) {
        self.name = name
        self.args = args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let argsJSON = try? container.decodeIfPresent(GeminiToolAnyCodable.self, forKey: .args) {
            args = argsJSON.value as? [String: Any]
        } else {
            args = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let args = args {
            let argsData = try JSONSerialization.data(withJSONObject: args)
            let argsJSON = try JSONDecoder().decode(GeminiToolJSONValue.self, from: argsData)
            try container.encode(argsJSON, forKey: .args)
        }
    }
}

/// Gemini 関数レスポンス（ツール実行結果）
private struct GeminiToolFunctionResponse: Codable {
    let name: String
    let response: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name, response
    }

    init(name: String, response: [String: Any]) {
        self.name = name
        self.response = response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let responseJSON = try? container.decode(GeminiToolAnyCodable.self, forKey: .response) {
            response = responseJSON.value as? [String: Any] ?? [:]
        } else {
            response = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        let responseData = try JSONSerialization.data(withJSONObject: response)
        let responseJSON = try JSONDecoder().decode(GeminiToolJSONValue.self, from: responseData)
        try container.encode(responseJSON, forKey: .response)
    }
}

/// Gemini 生成設定
private struct GeminiToolGenerationConfig: Encodable {
    var maxOutputTokens: Int
    var temperature: Double?
}

/// JSON 値の汎用エンコード/デコード用
private enum GeminiToolJSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([GeminiToolJSONValue])
    case object([String: GeminiToolJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([GeminiToolJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: GeminiToolJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

/// 任意の JSON 値をデコードするためのラッパー
private struct GeminiToolAnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([GeminiToolAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: GeminiToolAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
}

/// Gemini ツールレスポンスボディ
private struct GeminiToolResponseBody: Decodable {
    let candidates: [GeminiToolCandidate]?
    let promptFeedback: GeminiToolPromptFeedback?
    let usageMetadata: GeminiToolUsageMetadata?
}

/// Gemini 候補
private struct GeminiToolCandidate: Decodable {
    let content: GeminiToolContent?
    let finishReason: String?
    let safetyRatings: [GeminiToolSafetyRating]?
}

/// Gemini プロンプトフィードバック
private struct GeminiToolPromptFeedback: Decodable {
    let blockReason: String?
    let safetyRatings: [GeminiToolSafetyRating]?
}

/// Gemini 安全性評価
private struct GeminiToolSafetyRating: Decodable {
    let category: String?
    let probability: String?
}

/// Gemini 使用量メタデータ
private struct GeminiToolUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?
}

/// Gemini エラーレスポンス
private struct GeminiToolErrorResponse: Decodable {
    let error: GeminiToolError
}

/// Gemini エラー詳細
private struct GeminiToolError: Decodable {
    let code: Int
    let message: String
    let status: String
}
