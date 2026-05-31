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

// MARK: - GeminiClient + AgentCapableClient

extension GeminiClient: AgentCapableClient {
    /// エージェントステップを実行
    ///
    /// Google Gemini API を使用してエージェントステップを実行します。
    /// ツールコールと構造化出力の両方をサポートします。
    /// リトライ設定に基づいて、レート制限やサーバーエラー時に自動リトライを行います。
    public func executeAgentStep(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        _ = thinkingMode // Gemini は thinkingMode (on/off スイッチ) は持たず、thinkingConfig で表現する
        let endpoint = URL(string: "\(baseURL)/\(model.id):generateContent?key=\(apiKey)")!

        // HTTPリクエストを構築
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // リクエストボディを構築
        let body = buildAgentRequestBody(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            reasoningEffort: reasoningEffort,
            maxTokens: maxTokens
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        // リトライヘルパーを使用してリクエストを実行
        let retryHelper = AgentRetryHelper<GeminiRateLimitExtractor>(
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
                try parseAgentSuccessResponse(data: data, model: model.id)
            }
        )
    }

    // MARK: - Private Constants

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    /// `ReasoningEffort` を Gemini の `thinkingConfig` にマップする。
    /// 3 系: `thinkingLevel` 文字列。2.5 系: `thinkingBudget` 整数。
    /// モデルが minimal を許容しない場合は low に丸める。
    /// モデルが disable できないのに budget=0 が要求される場合は最小値に丸める。
    private static func thinkingConfig(for effort: ReasoningEffort, model: GeminiModel) -> GeminiThinkingConfig {
        switch model.thinkingControlStyle {
        case .level:
            let level: String
            switch effort {
            case .minimal: level = model.supportsMinimalThinkingLevel ? "minimal" : "low"
            case .low: level = "low"
            case .medium: level = "medium"
            case .high: level = "high"
            }
            return GeminiThinkingConfig(thinkingLevel: level, thinkingBudget: nil)
        case .budget:
            let budget: Int
            switch effort {
            case .minimal: budget = model.canDisableThinking ? 0 : 128
            case .low: budget = 1024
            case .medium: budget = 8192
            case .high: budget = 24576
            }
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: budget)
        case .unsupported:
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: nil)
        }
    }

    // MARK: - Private Helpers

    /// エージェントリクエストボディを構築
    private func buildAgentRequestBody(
        model: GeminiModel,
        messages: [LLMMessage],
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) -> GeminiAgentRequestBody {
        // コンテンツを構築
        var contents: [GeminiAgentContent] = []

        for message in messages {
            contents.append(contentsOf: convertToGeminiContent(message))
        }

        // システムインストラクション
        var systemInstruction: GeminiAgentContent?
        if let prompt = systemPrompt {
            systemInstruction = GeminiAgentContent(
                role: "user",
                parts: [GeminiAgentPart(text: prompt.render())]
            )
        }

        // 生成設定
        var generationConfig = GeminiAgentGenerationConfig(
            maxOutputTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: nil
        )

        // 構造化出力の設定
        if let schema = responseSchema {
            let adapter = GeminiSchemaAdapter()
            generationConfig.responseMimeType = "application/json"
            generationConfig.responseSchema = adapter.adapt(schema)
        }

        // thinkingConfig: モデルが対応している場合のみ送る。
        // 非対応モデルにこのフィールドを送るとエラーになる。
        if let effort = reasoningEffort, model.supportsThinkingConfig {
            generationConfig.thinkingConfig = Self.thinkingConfig(for: effort, model: model)
        }

        // ツール設定（空の場合は nil）
        let geminiTools: [GeminiAgentToolDef]?
        let toolConfig: GeminiAgentToolConfig?

        if !tools.isEmpty {
            let functionDeclarations = tools.toGeminiFormat().map { GeminiAgentFunctionDeclaration(dict: $0) }
            geminiTools = [GeminiAgentToolDef(functionDeclarations: functionDeclarations)]
            toolConfig = toolChoice.map { mapToolChoice($0, tools: tools) }
        } else {
            geminiTools = nil
            toolConfig = nil
        }

        return GeminiAgentRequestBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            tools: geminiTools,
            toolConfig: toolConfig
        )
    }

    /// LLMMessage を Gemini コンテンツ形式に変換
    private func convertToGeminiContent(_ message: LLMMessage) -> [GeminiAgentContent] {
        let role = message.role == .user ? "user" : "model"
        var parts: [GeminiAgentPart] = []
        var toolResultParts: [GeminiAgentPart] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                parts.append(GeminiAgentPart(text: text))

            case .toolUse(let id, let name, let input):
                // ツール呼び出し（モデルからの応答）
                let args: [String: Any]?
                if let argsDict = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
                    args = argsDict
                } else {
                    args = nil
                }
                let functionCall = GeminiAgentFunctionCall(name: name, args: args)
                let sig = GeminiThoughtSignatureEncoding.decodeThoughtSignature(from: id)
                parts.append(GeminiAgentPart(functionCall: functionCall, thoughtSignature: sig))

            case .toolResult(_, let name, let content):
                // ツール結果（ユーザーからの応答）
                let responseDict: [String: Any] = ["result": content.contentValue]
                let functionResponse = GeminiAgentFunctionResponse(name: name, response: responseDict)
                toolResultParts.append(GeminiAgentPart(functionResponse: functionResponse))

            case .image(let imageContent):
                if let part = convertMediaToAgentPart(source: imageContent.source, mimeType: imageContent.mediaType) {
                    parts.append(part)
                }
            case .audio(let audioContent):
                if let part = convertMediaToAgentPart(source: audioContent.source, mimeType: audioContent.mediaType) {
                    parts.append(part)
                }
            case .video(let videoContent):
                if let part = convertMediaToAgentPart(source: videoContent.source, mimeType: videoContent.mediaType) {
                    parts.append(part)
                }
            case .thinking:
                break // Gemini では thinking は無視
            }
        }

        var contents: [GeminiAgentContent] = []

        // 通常のパーツ（テキストとツール呼び出し）
        if !parts.isEmpty {
            contents.append(GeminiAgentContent(role: role, parts: parts))
        }

        // ツール結果は常にuserロールで送信
        if !toolResultParts.isEmpty {
            contents.append(GeminiAgentContent(role: "user", parts: toolResultParts))
        }

        return contents
    }

    /// ToolChoice を Gemini 形式に変換
    private func mapToolChoice(_ choice: ToolChoice, tools: ToolSet) -> GeminiAgentToolConfig {
        let config: GeminiAgentFunctionCallingConfig
        switch choice {
        case .auto:
            config = GeminiAgentFunctionCallingConfig(mode: "AUTO", allowedFunctionNames: nil)
        case .disabled:
            config = GeminiAgentFunctionCallingConfig(mode: "NONE", allowedFunctionNames: nil)
        case .required:
            config = GeminiAgentFunctionCallingConfig(mode: "ANY", allowedFunctionNames: nil)
        case .tool(let name):
            config = GeminiAgentFunctionCallingConfig(mode: "ANY", allowedFunctionNames: [name])
        }
        return GeminiAgentToolConfig(functionCallingConfig: config)
    }

    /// メディアソースを Agent API パーツに変換
    private func convertMediaToAgentPart<T: MediaType>(source: MediaSource, mimeType: T) -> GeminiAgentPart? {
        switch source {
        case .base64(let data):
            let base64String = data.base64EncodedString()
            let inlineData = GeminiAgentInlineData(mimeType: mimeType.mimeType, data: base64String)
            return GeminiAgentPart(inlineData: inlineData)
        case .url(let url):
            let fileData = GeminiAgentFileData(mimeType: mimeType.mimeType, fileUri: url.absoluteString)
            return GeminiAgentPart(fileData: fileData)
        case .fileReference(let id):
            let fileData = GeminiAgentFileData(mimeType: mimeType.mimeType, fileUri: id)
            return GeminiAgentPart(fileData: fileData)
        }
    }

    /// エラーステータスコードから LLMError を生成
    private func parseAgentError(data: Data, statusCode: Int) throws -> LLMError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimitExceeded
        case 400:
            let errorResponse = try? JSONDecoder().decode(GeminiAgentErrorResponse.self, from: data)
            return .invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(GeminiAgentErrorResponse.self, from: data)
            return .modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(GeminiAgentErrorResponse.self, from: data)
            return .serverError(statusCode, errorResponse?.error.message ?? "Server error")
        default:
            return .serverError(statusCode, "Unexpected status code")
        }
    }

    /// 成功レスポンスから LLMResponse を生成
    private func parseAgentSuccessResponse(data: Data, model: String) throws -> LLMResponse {
        let decoder = JSONDecoder()

        let geminiResponse: GeminiAgentResponseBody
        do {
            geminiResponse = try decoder.decode(GeminiAgentResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return convertToLLMResponse(geminiResponse, model: model)
    }

    /// Gemini レスポンスから LLMResponse を生成
    private func convertToLLMResponse(_ response: GeminiAgentResponseBody, model: String) -> LLMResponse {
        // 最初の候補を取得
        guard let candidate = response.candidates?.first,
              let content = candidate.content else {
            let usage: TokenUsage
            if let usageMetadata = response.usageMetadata {
                usage = GeminiUsageNormalizer.normalize(usageMetadata)
            } else {
                usage = TokenUsage.zero
            }
            return LLMResponse(
                content: [],
                model: model,
                usage: usage,
                stopReason: nil
            )
        }

        var contentBlocks: [LLMResponse.ContentBlock] = []

        // パーツを処理
        for part in content.parts {
            // テキストコンテンツ
            if let text = part.text {
                contentBlocks.append(.text(text))
            }
            // 関数呼び出し
            if let functionCall = part.functionCall {
                if let argsData = try? JSONSerialization.data(withJSONObject: functionCall.args ?? [:]) {
                    contentBlocks.append(.toolUse(
                        id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                        name: functionCall.name,
                        input: argsData
                    ))
                }
            }
        }

        // 停止理由をマッピング
        let stopReason = mapStopReason(candidate.finishReason)

        // 使用量を取得
        let usage: TokenUsage
        if let usageMetadata = response.usageMetadata {
            usage = GeminiUsageNormalizer.normalize(usageMetadata)
        } else {
            usage = TokenUsage.zero
        }

        return LLMResponse(
            content: contentBlocks,
            model: model,
            usage: usage,
            stopReason: stopReason
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

// MARK: - Gemini Agent Request/Response Types

/// Gemini エージェントリクエストボディ
private struct GeminiAgentRequestBody: Encodable {
    let contents: [GeminiAgentContent]
    let systemInstruction: GeminiAgentContent?
    let generationConfig: GeminiAgentGenerationConfig
    let tools: [GeminiAgentToolDef]?
    let toolConfig: GeminiAgentToolConfig?
}

/// Gemini ツール定義
private struct GeminiAgentToolDef: Encodable {
    let functionDeclarations: [GeminiAgentFunctionDeclaration]
}

/// Gemini 関数宣言
private struct GeminiAgentFunctionDeclaration: Encodable {
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
        let paramsJSON = try JSONDecoder().decode(AgentGeminiJSONValue.self, from: paramsData)
        try container.encode(paramsJSON, forKey: .parameters)
    }
}

/// Gemini ツール設定
private struct GeminiAgentToolConfig: Encodable {
    let functionCallingConfig: GeminiAgentFunctionCallingConfig
}

/// Gemini 関数呼び出し設定
private struct GeminiAgentFunctionCallingConfig: Encodable {
    let mode: String
    let allowedFunctionNames: [String]?
}

/// Gemini 生成設定
private struct GeminiAgentGenerationConfig: Encodable {
    var maxOutputTokens: Int
    var temperature: Double?
    var responseMimeType: String?
    var responseSchema: JSONSchema?
    var thinkingConfig: GeminiThinkingConfig?
}

/// Gemini thinking 設定。Gemini 3 系は `thinkingLevel`、2.5 系は `thinkingBudget` を使う。
/// 非対応モデルにこれを送るとエラーになるため、呼び出し側で gate する。
private struct GeminiThinkingConfig: Encodable {
    var thinkingLevel: String?
    var thinkingBudget: Int?
}

/// Gemini コンテンツ
private struct GeminiAgentContent: Codable {
    let role: String?
    let parts: [GeminiAgentPart]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        parts = (try? container.decodeIfPresent([GeminiAgentPart].self, forKey: .parts)) ?? []
    }

    init(role: String?, parts: [GeminiAgentPart]) {
        self.role = role
        self.parts = parts
    }
}

/// Gemini パーツ
private struct GeminiAgentPart: Codable {
    let text: String?
    let functionCall: GeminiAgentFunctionCall?
    let functionResponse: GeminiAgentFunctionResponse?
    let inlineData: GeminiAgentInlineData?
    let fileData: GeminiAgentFileData?
    let thoughtSignature: String?

    init(text: String) {
        self.text = text
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiAgentFunctionCall) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiAgentFunctionCall, thoughtSignature: String?) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = thoughtSignature
    }

    init(functionResponse: GeminiAgentFunctionResponse) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = functionResponse
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(inlineData: GeminiAgentInlineData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = inlineData
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(fileData: GeminiAgentFileData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = fileData
        self.thoughtSignature = nil
    }
}

/// Gemini インラインデータ（Base64エンコードされたメディア）
private struct GeminiAgentInlineData: Codable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

/// Gemini ファイルデータ（URL/ファイル参照）
private struct GeminiAgentFileData: Codable {
    let mimeType: String
    let fileUri: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case fileUri = "file_uri"
    }
}

/// Gemini 関数呼び出し
private struct GeminiAgentFunctionCall: Codable {
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
        if let argsJSON = try? container.decodeIfPresent(AgentGeminiAnyCodable.self, forKey: .args) {
            args = argsJSON.anyValue as? [String: Any]
        } else {
            args = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let args = args {
            let argsData = try JSONSerialization.data(withJSONObject: args)
            let argsJSON = try JSONDecoder().decode(AgentGeminiJSONValue.self, from: argsData)
            try container.encode(argsJSON, forKey: .args)
        }
    }
}

/// Gemini 関数レスポンス（ツール実行結果）
private struct GeminiAgentFunctionResponse: Codable {
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
        if let responseJSON = try? container.decode(AgentGeminiAnyCodable.self, forKey: .response) {
            response = responseJSON.anyValue as? [String: Any] ?? [:]
        } else {
            response = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        let responseData = try JSONSerialization.data(withJSONObject: response)
        let responseJSON = try JSONDecoder().decode(AgentGeminiJSONValue.self, from: responseData)
        try container.encode(responseJSON, forKey: .response)
    }
}

/// JSON 値の汎用エンコード/デコード用
private typealias AgentGeminiJSONValue = StructuredValue

/// 任意の JSON 値をデコードするためのラッパー
private typealias AgentGeminiAnyCodable = StructuredValue

/// Gemini エージェントレスポンスボディ
private struct GeminiAgentResponseBody: Decodable {
    let candidates: [GeminiAgentCandidate]?
    let promptFeedback: GeminiAgentPromptFeedback?
    let usageMetadata: GeminiAgentUsageMetadata?
}

/// Gemini 候補
private struct GeminiAgentCandidate: Decodable {
    let content: GeminiAgentContent?
    let finishReason: String?
    let safetyRatings: [GeminiAgentSafetyRating]?
}

/// Gemini プロンプトフィードバック
private struct GeminiAgentPromptFeedback: Decodable {
    let blockReason: String?
    let safetyRatings: [GeminiAgentSafetyRating]?
}

/// Gemini 安全性評価
private struct GeminiAgentSafetyRating: Decodable {
    let category: String?
    let probability: String?
}

/// Gemini 使用量メタデータ
private struct GeminiAgentUsageMetadata: Decodable, GeminiUsageMetadataRaw {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?
}

/// Gemini エラーレスポンス
private struct GeminiAgentErrorResponse: Decodable {
    let error: GeminiAgentError
}

/// Gemini エラー詳細
private struct GeminiAgentError: Decodable {
    let code: Int
    let message: String
    let status: String
}
