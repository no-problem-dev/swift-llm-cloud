import Foundation
import LLMClient

/// `/v1/responses` のリクエストボディ。
///
/// Chat Completions の `OpenAICompatibleRequestBody` とは形が大きく違うため、
/// LLMCloudOpenAI 内で独立して定義する。
package struct OpenAIResponsesRequestBody: Encodable, Sendable {
    package let model: String
    /// システムプロンプト相当（Responses API では top-level）
    package let instructions: String?
    package let input: [OpenAIResponsesInputItem]
    package let tools: [OpenAIResponsesToolDef]?
    package let toolChoice: OpenAIResponsesToolChoice?
    /// `{"effort": "low"}` 形式
    package let reasoning: OpenAIResponsesReasoningConfig?
    /// 構造化出力（`{"format": {...}}`）
    package let text: OpenAIResponsesTextConfig?
    /// Chat Completions の `max_completion_tokens` 相当
    package let maxOutputTokens: Int
    /// stateless 運用: false 固定（previous_response_id を使わないため）
    package let store: Bool

    package init(
        model: String,
        instructions: String?,
        input: [OpenAIResponsesInputItem],
        tools: [OpenAIResponsesToolDef]?,
        toolChoice: OpenAIResponsesToolChoice?,
        reasoning: OpenAIResponsesReasoningConfig?,
        text: OpenAIResponsesTextConfig?,
        maxOutputTokens: Int,
        store: Bool = false
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
    }
}

// MARK: - Reasoning

/// `reasoning` パラメータの設定。
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

/// Responses API のツール定義（フラット形式: `{type, name, description, parameters, strict}`）。
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

/// `text.format` の設定。Responses API では `response_format` が `text.format` に移行。
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
