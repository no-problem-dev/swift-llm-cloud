import Foundation
import LLMClient

/// Request body for the Responses API.
///
/// The shape differs enough from the Chat Completions body that it is defined separately rather
/// than shared with the OpenAI-compatible types.
package struct OpenAIResponsesRequestBody: Encodable, Sendable {
    package let model: String
    /// System prompt. The Responses API takes it as a top-level field instead of as a message
    /// with a system role.
    package let instructions: String?
    package let input: [OpenAIResponsesInputItem]
    package let tools: [OpenAIResponsesToolDef]?
    package let toolChoice: OpenAIResponsesToolChoice?
    /// Reasoning budget, encoded as `{"effort": "low"}`. Only reasoning models accept it.
    package let reasoning: OpenAIResponsesReasoningConfig?
    /// Structured output, encoded as `{"format": {...}}`. This replaces the Chat Completions
    /// `response_format`.
    package let text: OpenAIResponsesTextConfig?
    /// Output budget, the counterpart of `max_completion_tokens`. On reasoning models it covers
    /// reasoning tokens as well as visible output.
    package let maxOutputTokens: Int
    /// Whether OpenAI keeps a server-side copy of the response. It is always false here, since
    /// this client never sends `previous_response_id` and replays the whole history each turn.
    package let store: Bool
    /// Whether to stream the response as SSE. When false the key is omitted entirely, which keeps
    /// the non-streaming request byte-identical to what it was before streaming existed.
    package let stream: Bool

    package init(
        model: String,
        instructions: String?,
        input: [OpenAIResponsesInputItem],
        tools: [OpenAIResponsesToolDef]?,
        toolChoice: OpenAIResponsesToolChoice?,
        reasoning: OpenAIResponsesReasoningConfig?,
        text: OpenAIResponsesTextConfig?,
        maxOutputTokens: Int,
        store: Bool = false,
        stream: Bool = false
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoning = reasoning
        self.text = text
        self.maxOutputTokens = maxOutputTokens
        self.store = store
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case toolChoice = "tool_choice"
        case reasoning
        case text
        case maxOutputTokens = "max_output_tokens"
        case store
        case stream
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if let instructions {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encode(input, forKey: .input)
        if let tools {
            try container.encode(tools, forKey: .tools)
        }
        if let toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        if let reasoning {
            try container.encode(reasoning, forKey: .reasoning)
        }
        if let text {
            try container.encode(text, forKey: .text)
        }
        try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encode(store, forKey: .store)
        if stream {
            try container.encode(true, forKey: .stream)
        }
    }
}

// MARK: - Reasoning

/// Value of the `reasoning` parameter.
///
/// Sending an effort a model does not accept fails the whole request, so callers clamp it to a
/// supported step before constructing this.
package struct OpenAIResponsesReasoningConfig: Encodable, Sendable {
    package let effort: String

    package init(effort: ReasoningEffort) {
        self.effort = effort.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case effort
    }
}

// MARK: - Tool Definition

/// A function tool as the Responses API declares it.
///
/// The shape is flat — `{type, name, description, parameters, strict}` — where Chat Completions
/// nests everything but `type` under a `function` key.
package struct OpenAIResponsesToolDef: Encodable, Sendable {
    package let type: String
    package let name: String
    package let description: String
    package let parameters: JSONSchema
    package let strict: Bool

    package init(
        name: String,
        description: String,
        parameters: JSONSchema,
        strict: Bool = true
    ) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case parameters
        case strict
    }
}

// MARK: - Tool Choice

package enum OpenAIResponsesToolChoice: Encodable, Sendable {
    case auto
    case required
    case none
    case tool(name: String)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .required:
            try container.encode("required")
        case .none:
            try container.encode("none")
        case .tool(let name):
            try container.encode(ToolChoiceObject(type: "function", name: name))
        }
    }

    private struct ToolChoiceObject: Encodable {
        let type: String
        let name: String
    }
}

// MARK: - Structured Output

/// Value of the `text` parameter, which carries the structured-output format.
///
/// The Responses API moved what Chat Completions called `response_format` to `text.format`.
package struct OpenAIResponsesTextConfig: Encodable, Sendable {
    package let format: OpenAIResponsesFormat

    package init(format: OpenAIResponsesFormat) {
        self.format = format
    }
}

package struct OpenAIResponsesFormat: Encodable, Sendable {
    package let type: String
    package let name: String
    package let schema: JSONSchema
    package let strict: Bool

    package init(name: String, schema: JSONSchema, strict: Bool = true) {
        self.type = "json_schema"
        self.name = name
        self.schema = schema
        self.strict = strict
    }

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case schema
        case strict
    }
}
