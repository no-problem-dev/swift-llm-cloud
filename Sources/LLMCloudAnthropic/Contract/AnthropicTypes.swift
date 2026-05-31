import Foundation
import StructuredDataCore
import JSONParsing
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
    let thinking: AnthropicThinkingConfig?

    init(
        model: String,
        messages: [AnthropicMessage],
        system: String? = nil,
        maxTokens: Int,
        temperature: Double? = nil,
        outputConfig: AnthropicOutputConfig? = nil,
        tools: [AnthropicToolDef]? = nil,
        toolChoice: AnthropicToolChoiceValue? = nil,
        stream: Bool? = nil,
        thinking: AnthropicThinkingConfig? = nil
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
        self.thinking = thinking
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools, stream, thinking
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
        try container.encodeIfPresent(thinking, forKey: .thinking)
    }
}

struct AnthropicThinkingConfig: Encodable, Sendable {
    let type: String
    let budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

struct AnthropicToolDef: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
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

    private enum Kind: String, Encodable {
        case auto, any, tool
    }

    private struct Choice: Encodable {
        let type: Kind
        var name: String?
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto, .none:
            try container.encode(Choice(type: .auto))
        case .any:
            try container.encode(Choice(type: .any))
        case .tool(let name):
            try container.encode(Choice(type: .tool, name: name))
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
            try container.encode(TextBlock(text: text))
        case .thinking(let text, let signature):
            try container.encode(ThinkingBlock(thinking: text, signature: signature))
        case .toolUse(let id, let name, let input):
            let inputJSON = (try? JSONParser().parse(input)) ?? .object(OrderedObject([]))
            try container.encode(ToolUseBlock(id: id, name: name, input: inputJSON))
        case .toolResult(let toolUseId, let resultContent, let isError):
            try container.encode(ToolResultBlock(toolUseId: toolUseId, content: resultContent, isError: isError ? true : nil))
        case .image(let imageContent):
            try container.encode(ImageBlock(source: ImageBlock.Source(imageContent)))
        }
    }

    private struct TextBlock: Encodable {
        let type = "text"
        let text: String
    }

    private struct ThinkingBlock: Encodable {
        let type = "thinking"
        let thinking: String
        let signature: String?
    }

    private struct ToolUseBlock: Encodable {
        let type = "tool_use"
        let id: String
        let name: String
        let input: JSONValue
    }

    private struct ToolResultBlock: Encodable {
        let type = "tool_result"
        let toolUseId: String
        let content: String
        let isError: Bool?
        enum CodingKeys: String, CodingKey {
            case type, content
            case toolUseId = "tool_use_id"
            case isError = "is_error"
        }
    }

    private struct ImageBlock: Encodable {
        let type = "image"
        let source: Source

        struct Source: Encodable {
            let type: String
            let mediaType: String?
            let data: String?
            let url: String?

            enum CodingKeys: String, CodingKey {
                case type, data, url
                case mediaType = "media_type"
            }

            init(_ image: ImageContent) {
                switch image.source {
                case .base64(let data):
                    type = "base64"; mediaType = image.mediaType.rawValue; self.data = data.base64EncodedString(); url = nil
                case .url(let imageURL):
                    type = "url"; mediaType = nil; data = nil; url = imageURL.absoluteString
                case .fileReference:
                    type = "base64"; mediaType = image.mediaType.rawValue; data = ""; url = nil
                }
            }
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

