import Foundation
import LLMClient
import LLMCloudClient

/// OpenAI 互換 API リクエストボディ
package struct OpenAICompatibleRequestBody: Encodable, Sendable {
    package let model: String
    package let messages: [OpenAICompatibleMessage]
    package let maxTokens: Int
    /// 最大トークン数を送るフィールド名（プロバイダーごとに max_completion_tokens / max_tokens）。
    package let maxTokensParameter: OpenAICompatibleMaxTokensParameter
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
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens,
        temperature: Double?,
        responseFormat: OpenAICompatibleResponseFormat?,
        tools: [OpenAICompatibleToolDef]?,
        toolChoice: OpenAICompatibleToolChoice?,
        reasoningEffort: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxCompletionTokens
        self.maxTokensParameter = maxTokensParameter
        self.temperature = temperature
        self.responseFormat = responseFormat
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case tools
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
    }

    /// 最大トークン数フィールドを実行時に決まる名前で出力するための動的キー。
    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        // 最大トークン数はプロバイダー指定のフィールド名で出力する。
        var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
        try dynamic.encode(maxTokens, forKey: DynamicCodingKey(maxTokensParameter.rawValue))
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

/// JSON Schema ラッパー（schema は `WireSchema` でキーワードを verbatim 出力）
package struct OpenAICompatibleJSONSchemaWrapper: Encodable, Sendable {
    package let name: String
    package let strict: Bool
    package let schema: WireSchema

    package init(name: String, strict: Bool, schema: JSONSchema) {
        self.name = name
        self.strict = strict
        self.schema = WireSchema(schema)
    }
}
