import Foundation
import StructuredDataCore
import JSONParsing
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - Cache Control

/// A prompt cache breakpoint marking how far back the prompt should be reused.
///
/// Serialized as Anthropic's `cache_control` object: `{"type":"ephemeral"}`, or
/// `{"type":"ephemeral","ttl":"5m"}` / `"1h"` when a TTL is set. Anthropic caches everything
/// *before* the marked block, so where the breakpoint lands decides what gets cached.
struct AnthropicCacheControl: Encodable, Sendable, Equatable {
    let type = "ephemeral"
    let ttl: String?

    enum CodingKeys: String, CodingKey {
        case type, ttl
    }

    /// Rounds a requested cache lifetime to one of the two TTLs Anthropic accepts.
    ///
    /// Anthropic offers only `"5m"` and `"1h"`, so anything up to five minutes becomes `"5m"`
    /// and anything longer becomes `"1h"` — a 10-minute request is rounded up, not down.
    init(ttl: Duration) {
        self.ttl = ttl <= .seconds(300) ? "5m" : "1h"
    }

    /// Beta feature name that must be sent before a one-hour TTL is accepted.
    static let extendedTTLBeta = "extended-cache-ttl-2025-04-11"

    var requiresExtendedTTLBeta: Bool { ttl == "1h" }
}

// MARK: - Request Types

/// Request body for the create-message endpoint.
///
/// `maxTokens` is non-optional because Anthropic requires `max_tokens` on every request; there
/// is no server-side default to fall back on, so callers pick one before reaching this type.
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

        // Lower the caching intent into a breakpoint placement. Anthropic orders the prompt as
        // tools → system → messages, and one breakpoint caches the whole prefix up to it, so a
        // single marker suffices: put it at the end of the system block, or on the last tool if
        // there is no system block. With neither present the policy is a no-op.
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

    /// Beta names this body needs, currently only the one-hour cache TTL opt-in.
    ///
    /// Non-empty only when a breakpoint was actually placed and rounded to `"1h"`; a policy that
    /// found nothing to mark contributes nothing here.
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
    /// The schema is held as a wire-ready value so the body's snake_case key strategy cannot
    /// rewrite JSON Schema keywords such as `additionalProperties` into `additional_properties`.
    let inputSchema: WireSchema
    let cacheControl: AnthropicCacheControl?

    init(name: String, description: String, inputSchema: JSONSchema, cacheControl: AnthropicCacheControl? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = WireSchema(inputSchema)
        self.cacheControl = cacheControl
    }

    func withCacheControl(_ cacheControl: AnthropicCacheControl) -> AnthropicToolDef {
        AnthropicToolDef(name: name, description: description, inputSchema: inputSchema.schema, cacheControl: cacheControl)
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

/// Anthropic's `tool_choice`, in the four shapes the Messages API accepts.
///
/// The case is deliberately spelled `disabled` rather than `none`: this type is almost always held
/// as an `AnthropicToolChoiceValue?`, and a case named `none` shadows `Optional.none` at every use
/// site, so `?? .auto` and `== .none` stop meaning what they read as.
enum AnthropicToolChoiceValue: Encodable, Sendable {
    case auto
    case any
    case disabled
    case tool(String)

    init(_ choice: ToolChoice) {
        switch choice {
        case .auto: self = .auto
        case .disabled: self = .disabled
        case .required: self = .any
        case .tool(let name): self = .tool(name)
        }
    }

    private enum Kind: String, Encodable {
        case auto, any, tool, none
    }

    private struct Choice: Encodable {
        let type: Kind
        var name: String?
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode(Choice(type: .auto))
        case .any:
            try container.encode(Choice(type: .any))
        case .disabled:
            // `{"type":"none"}` is what stops Claude calling a tool. The tools array still goes out
            // so the cached prefix survives the turn — suppressing the call is not the same as
            // withdrawing the definitions.
            try container.encode(Choice(type: .none))
        case .tool(let name):
            try container.encode(Choice(type: .tool, name: name))
        }
    }
}

// MARK: - Message Types

/// One turn of the conversation, always encoded with a block array rather than a bare string.
struct AnthropicMessage: Encodable, Sendable {
    let role: String
    let content: [AnthropicMessageContent]
}

/// A single content block inside a message.
///
/// Anthropic identifies a tool result by the `tool_use_id` of the call it answers and carries it
/// as a content block, rather than as a dedicated message role the way OpenAI does. Replaying a
/// `thinking` block requires the signature Anthropic issued with it, so the two travel together.
///
/// Tool arguments arrive here as raw JSON bytes and are re-parsed before encoding. Bytes that do
/// not parse are sent as an empty object, which is how a tool call whose streamed arguments were
/// cut short ends up replayed with no arguments at all.
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

/// Asks Anthropic to constrain generation to a JSON Schema.
///
/// Sent as `output_config.format` with `type` set to `json_schema`. Anthropic then enforces the
/// schema during decoding rather than merely being asked to follow it, so the reply parses
/// without repair prompts.
struct AnthropicOutputFormat: Encodable, Sendable {
    let type: String
    /// The schema is held as a wire-ready value so the body's snake_case key strategy cannot
    /// rewrite JSON Schema keywords such as `additionalProperties` into `additional_properties`.
    let schema: WireSchema

    init(type: String, schema: JSONSchema) {
        self.type = type
        self.schema = WireSchema(schema)
    }
}

struct AnthropicOutputConfig: Encodable, Sendable {
    let format: AnthropicOutputFormat?
}

// MARK: - Response Types

/// Non-streaming reply from the create-message endpoint.
///
/// A single reply can mix block kinds — text, thinking, and one or more tool uses — so callers
/// read `content` as a list rather than expecting one answer, and consult `stopReason` to see
/// whether the turn ended because tools were requested or because `max_tokens` ran out.
struct AnthropicResponseBody: Decodable, Sendable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage
}

/// One decoded block of a reply, flattened across every block kind Anthropic can return.
///
/// Which fields are populated depends on `type`: text blocks carry `text`, tool uses carry
/// `id`, `name`, and an already-parsed `input` object, and thinking blocks carry the `signature`
/// needed to replay them in a later turn. Thinking prose is read from `text` here, whereas the
/// request side writes it under a `thinking` key.
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

/// Token counters exactly as Anthropic reports them, before normalization.
///
/// `inputTokens` here counts only the fresh part of the prompt: cache reads and cache writes are
/// reported separately in `cacheReadInputTokens` and `cacheCreationInputTokens` and are *not*
/// included in it. Anything comparing providers should go through ``AnthropicUsageNormalizer``
/// rather than reading these fields directly.
struct AnthropicUsage: Decodable, Sendable, AnthropicUsageRaw {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

// MARK: - JSON Helper Types

/// Generic JSON value used for arbitrary payloads such as tool arguments.
typealias JSONValue = StructuredValue

