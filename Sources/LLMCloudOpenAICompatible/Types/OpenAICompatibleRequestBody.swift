import Foundation
import LLMClient

/// OpenAI 互換 API リクエストボディ
package struct OpenAICompatibleRequestBody: Encodable, Sendable {
    package let model: String
    package let messages: [OpenAICompatibleMessage]
    package let maxCompletionTokens: Int
    package let temperature: Double?
    package let responseFormat: OpenAICompatibleResponseFormat?
    package let tools: [OpenAICompatibleToolDef]?
    package let toolChoice: OpenAICompatibleToolChoice?
    /// OpenAI GPT-5 系の `reasoning_effort`。nil の場合は API デフォルト。
    package let reasoningEffort: String?

    package init(
        model: String,
        messages: [OpenAICompatibleMessage],
        maxCompletionTokens: Int,
        temperature: Double?,
        responseFormat: OpenAICompatibleResponseFormat?,
        tools: [OpenAICompatibleToolDef]?,
        toolChoice: OpenAICompatibleToolChoice?,
        reasoningEffort: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.maxCompletionTokens = maxCompletionTokens
        self.temperature = temperature
        self.responseFormat = responseFormat
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case temperature
        case responseFormat = "response_format"
        case tools
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(maxCompletionTokens, forKey: .maxCompletionTokens)
        if let temperature = temperature {
            try container.encode(temperature, forKey: .temperature)
        }
        if let responseFormat = responseFormat {
            try container.encode(responseFormat, forKey: .responseFormat)
        }
        if let tools = tools {
            try container.encode(tools, forKey: .tools)
        }
        if let toolChoice = toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        if let reasoningEffort = reasoningEffort {
            try container.encode(reasoningEffort, forKey: .reasoningEffort)
        }
    }
}

/// OpenAI 互換レスポンスフォーマット設定
package struct OpenAICompatibleResponseFormat: Encodable, Sendable {
    package let type: String
    package let jsonSchema: OpenAICompatibleJSONSchemaWrapper

    package init(type: String, jsonSchema: OpenAICompatibleJSONSchemaWrapper) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// JSON Schema ラッパー
package struct OpenAICompatibleJSONSchemaWrapper: Encodable, Sendable {
    package let name: String
    package let strict: Bool
    package let schema: JSONSchema

    package init(name: String, strict: Bool, schema: JSONSchema) {
        self.name = name
        self.strict = strict
        self.schema = schema
    }
}
