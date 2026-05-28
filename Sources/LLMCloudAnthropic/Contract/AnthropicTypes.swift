import Foundation
import LLMClient

// MARK: - Request Types

/// Anthropic API リクエストボディ
struct AnthropicRequestBody: Encodable, Sendable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let outputConfig: AnthropicOutputConfig?
    let stream: Bool?

    init(
        model: String,
        messages: [AnthropicMessage],
        system: String? = nil,
        maxTokens: Int,
        temperature: Double? = nil,
        outputConfig: AnthropicOutputConfig? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.system = system
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.outputConfig = outputConfig
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, stream
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(outputConfig, forKey: .outputConfig)
        try container.encodeIfPresent(stream, forKey: .stream)
    }
}

// MARK: - Message Types

/// Anthropic メッセージ
struct AnthropicMessage: Encodable, Sendable {
    let role: String
    let content: [AnthropicMessageContent]
}

/// Anthropic メッセージコンテンツ
enum AnthropicMessageContent: Encodable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: Data)
    case toolResult(toolUseId: String, content: String, isError: Bool)
    case image(ImageContent)

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

        case .image(let imageContent):
            var source: [String: JSONValue] = [:]

            switch imageContent.source {
            case .base64(let data):
                source["type"] = .string("base64")
                source["media_type"] = .string(imageContent.mediaType.rawValue)
                source["data"] = .string(data.base64EncodedString())
            case .url(let url):
                source["type"] = .string("url")
                source["url"] = .string(url.absoluteString)
            case .fileReference:
                source["type"] = .string("base64")
                source["media_type"] = .string(imageContent.mediaType.rawValue)
                source["data"] = .string("")
            }

            let dict: [String: JSONValue] = [
                "type": .string("image"),
                "source": .object(source)
            ]
            try container.encode(dict)
        }
    }
}

// MARK: - Output Config

/// Anthropic 出力フォーマット設定
struct AnthropicOutputFormat: Encodable, Sendable {
    let type: String
    let schema: JSONSchema
}

/// Anthropic 出力設定
struct AnthropicOutputConfig: Encodable, Sendable {
    let format: AnthropicOutputFormat?
}

// MARK: - Response Types

/// Anthropic API レスポンスボディ
struct AnthropicResponseBody: Decodable, Sendable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage
}

/// Anthropic コンテンツブロック
struct AnthropicContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent([String: JSONValue].self, forKey: .input)
    }
}

/// Anthropic 使用量
struct AnthropicUsage: Decodable, Sendable, AnthropicUsageRaw {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

// MARK: - JSON Helper Types

/// JSON 値の汎用エンコード/デコード用
enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

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
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
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
}

/// 任意の JSON 値をデコードするためのラッパー
struct AnyCodable: Decodable, Sendable {
    let value: any Sendable

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
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
}
