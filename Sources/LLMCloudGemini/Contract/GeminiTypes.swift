import Foundation
import StructuredDataCore
import LLMClient

// MARK: - Request Types

/// Gemini API リクエストボディ
struct GeminiRequestBody: Encodable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig
    let tools: [GeminiTool]?
    let toolConfig: GeminiToolConfig?
}

/// Gemini ツール
struct GeminiTool: Encodable, Sendable {
    let functionDeclarations: [GeminiFunctionDeclaration]
}

/// Gemini 関数宣言
struct GeminiFunctionDeclaration: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: JSONSchema

    init(name: String, description: String, parameters: JSONSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Gemini ツール設定
struct GeminiToolConfig: Encodable, Sendable {
    let functionCallingConfig: GeminiFunctionCallingConfig
}

/// Gemini 関数呼び出し設定
struct GeminiFunctionCallingConfig: Encodable, Sendable {
    let mode: String
    let allowedFunctionNames: [String]?
}

/// Gemini 生成設定
struct GeminiGenerationConfig: Encodable, Sendable {
    var maxOutputTokens: Int
    var temperature: Double?
    var responseMimeType: String?
    var responseSchema: JSONSchema?
    var thinkingConfig: GeminiThinkingConfig?
}

/// Gemini thinking 設定。3 系は thinkingLevel、2.5 系は thinkingBudget。
/// 非対応モデルに送るとエラーになるため呼び出し側で gate する。
struct GeminiThinkingConfig: Encodable, Sendable {
    var thinkingLevel: String?
    var thinkingBudget: Int?
}

// MARK: - Content Types

/// Gemini コンテンツ
struct GeminiContent: Codable, Sendable {
    let role: String
    let parts: [GeminiPart]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        parts = (try? container.decodeIfPresent([GeminiPart].self, forKey: .parts)) ?? []
    }

    init(role: String, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

/// Gemini パーツ
struct GeminiPart: Codable, Sendable {
    let text: String?
    let functionCall: GeminiFunctionCall?
    let functionResponse: GeminiFunctionResponse?
    let inlineData: GeminiInlineData?
    let fileData: GeminiFileData?
    let thoughtSignature: String?

    init(text: String) {
        self.text = text
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiFunctionCall) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiFunctionCall, thoughtSignature: String?) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = thoughtSignature
    }

    init(functionResponse: GeminiFunctionResponse) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = functionResponse
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(inlineData: GeminiInlineData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = inlineData
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(fileData: GeminiFileData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = fileData
        self.thoughtSignature = nil
    }
}

/// Gemini インラインデータ（Base64エンコードされたメディア）
struct GeminiInlineData: Codable, Sendable {
    let mimeType: String
    let data: String  // Base64エンコードされたデータ

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

/// Gemini ファイルデータ（File API経由でアップロードされたファイル）
struct GeminiFileData: Codable, Sendable {
    let mimeType: String
    let fileUri: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case fileUri = "file_uri"
    }
}

/// Gemini 関数呼び出し
struct GeminiFunctionCall: Codable, Sendable {
    let name: String
    let args: GeminiJSONValue?

    init(name: String, args: GeminiJSONValue?) {
        self.name = name
        self.args = args
    }
}

/// Gemini 関数レスポンス（ツール実行結果）
struct GeminiFunctionResponse: Codable, Sendable {
    let name: String
    let response: GeminiJSONValue

    init(name: String, response: GeminiJSONValue) {
        self.name = name
        self.response = response
    }
}

// MARK: - Response Types

/// Gemini API レスポンスボディ
struct GeminiResponseBody: Decodable, Sendable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
    let usageMetadata: GeminiUsageMetadata?
}

/// Gemini 候補
struct GeminiCandidate: Decodable, Sendable {
    let content: GeminiContent?
    let finishReason: String?
    let safetyRatings: [GeminiSafetyRating]?
}

/// Gemini プロンプトフィードバック
struct GeminiPromptFeedback: Decodable, Sendable {
    let blockReason: String?
    let safetyRatings: [GeminiSafetyRating]?
}

/// Gemini 安全性評価
struct GeminiSafetyRating: Decodable, Sendable {
    let category: String
    let probability: String
}

/// Gemini 使用量メタデータ
struct GeminiUsageMetadata: Decodable, Sendable, GeminiUsageMetadataRaw {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?
}

/// Gemini エラーレスポンス
struct GeminiErrorResponse: Decodable, Sendable {
    let error: GeminiErrorDetail
}

/// Gemini エラー詳細
struct GeminiErrorDetail: Decodable, Sendable {
    let code: Int
    let message: String
    let status: String
}

// MARK: - JSON Helper Types

/// JSON 値の汎用エンコード/デコード用
typealias GeminiJSONValue = StructuredValue
