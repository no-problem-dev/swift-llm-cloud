import Foundation
import StructuredDataCore
import LLMClient

// MARK: - Request Types

/// generateContent リクエストの「文脈」— 安定プレフィックスの渡し方
///
/// API 仕様上、`cachedContent` と `systemInstruction`/`tools`/`toolConfig` の同時送信は
/// 400 エラー（プレフィックスはキャッシュ作成時に固定済みのため）。
/// この排他関係を enum で表現し、不正な組み合わせを構築不能にする。
enum GeminiPromptContext: Sendable {
    /// プレフィックスをリクエストに直接含める
    case inline(systemInstruction: GeminiContent?, tools: [GeminiTool]?, toolConfig: GeminiToolConfig?)
    /// 作成済み `cachedContents` リソースを参照する（`cachedContents/{id}` 形式）
    case cached(name: String)
}

/// Gemini API リクエストボディ
struct GeminiRequestBody: Encodable, Sendable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
    let promptContext: GeminiPromptContext

    init(
        contents: [GeminiContent],
        generationConfig: GeminiGenerationConfig,
        promptContext: GeminiPromptContext
    ) {
        self.contents = contents
        self.generationConfig = generationConfig
        self.promptContext = promptContext
    }

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig
        case systemInstruction
        case tools
        case toolConfig
        case cachedContent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contents, forKey: .contents)
        try container.encode(generationConfig, forKey: .generationConfig)
        switch promptContext {
        case .inline(let systemInstruction, let tools, let toolConfig):
            try container.encodeIfPresent(systemInstruction, forKey: .systemInstruction)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(toolConfig, forKey: .toolConfig)
        case .cached(let name):
            try container.encode(name, forKey: .cachedContent)
        }
    }
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

enum GeminiFinishReason: String {
    case stop = "STOP"
    case maxTokens = "MAX_TOKENS"
    case safety = "SAFETY"

    static func stopReason(_ raw: String?) -> LLMResponse.StopReason? {
        switch raw.flatMap(Self.init) {
        case .stop: return .endTurn
        case .maxTokens: return .maxTokens
        case .safety, nil: return nil
        }
    }
}

// MARK: - JSON Helper Types

/// JSON 値の汎用エンコード/デコード用
typealias GeminiJSONValue = StructuredValue
