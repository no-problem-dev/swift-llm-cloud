import Foundation
import StructuredDataCore
import LLMClient
import LLMTool

// MARK: - Request Types

/// Anthropic API リクエストボディ
struct AnthropicRequestBody: Encodable, Sendable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let outputConfig: AnthropicOutputConfig?
    let tools: [AnthropicToolDef]?
    let toolChoice: AnthropicToolChoiceValue?
    let stream: Bool?

    init(
        model: String,
        messages: [AnthropicMessage],
        system: String? = nil,
        maxTokens: Int,
        temperature: Double? = nil,
        outputConfig: AnthropicOutputConfig? = nil,
        tools: [AnthropicToolDef]? = nil,
        toolChoice: AnthropicToolChoiceValue? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.system = system
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.outputConfig = outputConfig
        self.tools = tools
        self.toolChoice = toolChoice
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools, stream
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
        case toolChoice = "tool_choice"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(outputConfig, forKey: .outputConfig)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try container.encodeIfPresent(stream, forKey: .stream)
    }
}

struct AnthropicToolDef: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    init(dict: [String: Any]) throws {
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        let schemaDict = dict["input_schema"] as? [String: Any] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: schemaDict)
        self.inputSchema = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

enum AnthropicToolChoiceValue: Encodable, Sendable {
    case auto
    case any
    case none
    case tool(String)

    init(_ choice: ToolChoice) {
        switch choice {
        case .auto: self = .auto
        case .disabled: self = .none
        case .required: self = .any
        case .tool(let name): self = .tool(name)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto, .none:
            try container.encode(["type": "auto"])
        case .any:
            try container.encode(["type": "any"])
        case .tool(let name):
            try container.encode(["type": "tool", "name": name])
        }
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
    case thinking(text: String, signature: String?)
    case image(ImageContent)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .text(let text):
            try container.encode(["type": "text", "text": text])

        case .thinking(let text, let signature):
            var dict: [String: JSONValue] = [
                "type": .string("thinking"),
                "thinking": .string(text)
            ]
            if let signature {
                dict["signature"] = .string(signature)
            }
            try container.encode(dict)

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
                "source": .object(OrderedObject(source))
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
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent([String: JSONValue].self, forKey: .input)
        signature = try container.decodeIfPresent(String.self, forKey: .signature)
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

/// JSON 値の汎用エンコード/デコード用。swift-structured-data の StructuredValue に統一。
typealias JSONValue = StructuredValue

/// 任意の JSON 値をデコードするためのラッパー。`.anyValue` で Foundation の Any を得る。
typealias AnyCodable = StructuredValue
