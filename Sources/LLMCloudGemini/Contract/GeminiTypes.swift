import Foundation
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
    let inputSchema: [String: GeminiJSONValue]

    init(dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""

        if let params = dict["parameters"] as? [String: Any],
           let paramsData = try? JSONSerialization.data(withJSONObject: params),
           let decoded = try? JSONDecoder().decode([String: GeminiJSONValue].self, from: paramsData) {
            self.inputSchema = decoded
        } else {
            self.inputSchema = [:]
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "parameters"
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
    let args: [String: GeminiJSONValue]?

    init(name: String, args: [String: Any]?) {
        self.name = name
        if let args = args,
           let data = try? JSONSerialization.data(withJSONObject: args),
           let decoded = try? JSONDecoder().decode([String: GeminiJSONValue].self, from: data) {
            self.args = decoded
        } else {
            self.args = nil
        }
    }
}

/// Gemini 関数レスポンス（ツール実行結果）
struct GeminiFunctionResponse: Codable, Sendable {
    let name: String
    let response: [String: GeminiJSONValue]

    init(name: String, response: [String: Any]) {
        self.name = name
        if let data = try? JSONSerialization.data(withJSONObject: response),
           let decoded = try? JSONDecoder().decode([String: GeminiJSONValue].self, from: data) {
            self.response = decoded
        } else {
            self.response = [:]
        }
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
struct GeminiUsageMetadata: Decodable, Sendable {
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
enum GeminiJSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([GeminiJSONValue])
    case object([String: GeminiJSONValue])

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
        } else if let array = try? container.decode([GeminiJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: GeminiJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// JSONValue を [String: Any] に変換（JSONSerialization 互換用）
    func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }
}
