import Foundation
import StructuredDataCore
import JSONParsing
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - Cache Control

/// `cache_control` ブレークポイント。`{"type":"ephemeral"}` / ttl 指定時 `{"type":"ephemeral","ttl":"5m"|"1h"}`。
struct AnthropicCacheControl: Encodable, Sendable, Equatable {
    let type = "ephemeral"
    let ttl: String?

    enum CodingKeys: String, CodingKey {
        case type, ttl
    }

    /// `PromptCachePolicy.explicitPrefix(ttl:)` の `Duration` を Anthropic の ttl 文字列に丸める。
    /// `<= 5分` は `"5m"`、`> 5分` は `"1h"`。
    init(ttl: Duration) {
        self.ttl = ttl <= .seconds(300) ? "5m" : "1h"
    }

    /// `"1h"` を使う場合のみ必要な beta ヘッダー値。
    static let extendedTTLBeta = "extended-cache-ttl-2025-04-11"

    var requiresExtendedTTLBeta: Bool { ttl == "1h" }
}

// MARK: - Request Types

/// Anthropic API リクエストボディ
struct AnthropicRequestBody: Encodable, Sendable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let systemCacheControl: AnthropicCacheControl?
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
        thinking: AnthropicThinkingConfig? = nil,
        cachePolicy: PromptCachePolicy = .implicit
    ) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.outputConfig = outputConfig
        self.toolChoice = toolChoice
        self.stream = stream
        self.thinking = thinking

        // キャッシュ意図を Anthropic のブレークポイント配置に lowering する。
        // 階層は tools → system → messages。単一ブレークポイントはそこまでの全プレフィックスをキャッシュする:
        // system があれば system 末尾に、無く tools があれば最後の tool に置く（対象不在なら no-op）。
        guard case .explicitPrefix(let ttl) = cachePolicy else {
            self.system = system
            self.systemCacheControl = nil
            self.tools = tools
            return
        }
        let cacheControl = AnthropicCacheControl(ttl: ttl)
        if system != nil {
            self.system = system
            self.systemCacheControl = cacheControl
            self.tools = tools
        } else if let tools, !tools.isEmpty {
            self.system = system
            self.systemCacheControl = nil
            self.tools = tools.dropLast() + [tools[tools.count - 1].withCacheControl(cacheControl)]
        } else {
            self.system = system
            self.systemCacheControl = nil
            self.tools = tools
        }
    }

    /// `cachePolicy` が explicitPrefix かつ 1h の場合に必要な beta 値（対象不在なら付与しない）。
    var cacheBetaValues: [String] {
        if systemCacheControl?.requiresExtendedTTLBeta == true {
            return [AnthropicCacheControl.extendedTTLBeta]
        }
        if tools?.last?.cacheControl?.requiresExtendedTTLBeta == true {
            return [AnthropicCacheControl.extendedTTLBeta]
        }
        return []
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools, stream, thinking
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
        case toolChoice = "tool_choice"
    }

    private struct SystemTextBlock: Encodable {
        let type = "text"
        let text: String
        let cacheControl: AnthropicCacheControl

        enum CodingKeys: String, CodingKey {
            case type, text
            case cacheControl = "cache_control"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let system, let systemCacheControl {
            try container.encode([SystemTextBlock(text: system, cacheControl: systemCacheControl)], forKey: .system)
        } else {
            try container.encodeIfPresent(system, forKey: .system)
        }
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
    let cacheControl: AnthropicCacheControl?

    init(name: String, description: String, inputSchema: JSONSchema, cacheControl: AnthropicCacheControl? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.cacheControl = cacheControl
    }

    func withCacheControl(_ cacheControl: AnthropicCacheControl) -> AnthropicToolDef {
        AnthropicToolDef(name: name, description: description, inputSchema: inputSchema, cacheControl: cacheControl)
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
        case cacheControl = "cache_control"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
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
    case document(DocumentContent)

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
        case .document(let documentContent):
            try container.encode(DocumentBlock(documentContent))
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
            let fileId: String?

            enum CodingKeys: String, CodingKey {
                case type, data, url
                case mediaType = "media_type"
                case fileId = "file_id"
            }

            init(_ image: ImageContent) {
                (type, mediaType, data, url, fileId) = image.source.fold(
                    base64: { ("base64", image.mediaType.rawValue, $0.base64EncodedString(), nil, nil) },
                    url: { ("url", nil, nil, $0.absoluteString, nil) },
                    fileReference: { ("file", nil, nil, nil, $0) }
                )
            }
        }
    }

    private struct DocumentBlock: Encodable {
        let type = "document"
        let source: Source
        let title: String?
        let context: String?
        let citations: Citations?

        struct Source: Encodable {
            let type: String
            let mediaType: String?
            let data: String?
            let url: String?
            let fileId: String?

            enum CodingKeys: String, CodingKey {
                case type, data, url
                case mediaType = "media_type"
                case fileId = "file_id"
            }

            init(_ document: DocumentContent) {
                (type, mediaType, data, url, fileId) = document.source.fold(
                    base64: {
                        if document.mediaType == .plainText {
                            return ("text", DocumentMediaType.plainText.mimeType, String(decoding: $0, as: UTF8.self), nil, nil)
                        } else {
                            return ("base64", document.mediaType.mimeType, $0.base64EncodedString(), nil, nil)
                        }
                    },
                    url: { ("url", nil, nil, $0.absoluteString, nil) },
                    fileReference: { ("file", nil, nil, nil, $0) }
                )
            }
        }

        struct Citations: Encodable {
            let enabled: Bool
        }

        init(_ document: DocumentContent) {
            source = Source(document)
            title = document.title
            context = document.context
            citations = document.enableCitations ? Citations(enabled: true) : nil
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

