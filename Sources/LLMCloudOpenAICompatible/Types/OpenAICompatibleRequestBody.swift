import Foundation
import LLMClient
import LLMCloudClient

/// Chat completion request body, encoded by hand so the token cap can be renamed per vendor.
///
/// Synthesized encoding cannot give one property two different wire names, and that is exactly what
/// the token cap needs: `max_completion_tokens` for OpenAI, Groq, and xAI, `max_tokens` for
/// Mistral, DeepSeek, and OpenRouter. Optional fields are left out of the payload entirely when
/// nil rather than encoded as null, so no vendor sees a knob the caller did not set.
package struct OpenAICompatibleRequestBody: Encodable, Sendable {
    package let model: String
    package let messages: [OpenAICompatibleMessage]

    /// Cap on generated tokens, written under whichever name the parameter below selects.
    package let maxTokens: Int

    /// Which of the two field names the cap is written under.
    package let maxTokensParameter: OpenAICompatibleMaxTokensParameter

    package let temperature: Double?
    package let responseFormat: OpenAICompatibleResponseFormat?
    package let tools: [OpenAICompatibleToolDef]?
    package let toolChoice: OpenAICompatibleToolChoice?

    /// Value for the GPT-5 style reasoning effort knob, omitted when nil so the model's own default
    /// applies.
    package let reasoningEffort: String?

    /// Whether the vendor should answer with an SSE stream, omitted when nil.
    ///
    /// Only ever set to `true`, by the streaming agent step. The non-streaming paths leave it out
    /// rather than sending `false`, which keeps their request bodies byte-identical to what they
    /// were before streaming existed.
    ///
    /// `stream_options` is deliberately not sent alongside it. Mistral's API defines no such
    /// parameter at all, OpenRouter documents `include_usage` as having no effect, and the
    /// remaining vendors report usage on the stream without being asked — so the flag would buy
    /// nothing and risks a rejected request on the one vendor that has never heard of it.
    package let stream: Bool?

    package init(
        model: String,
        messages: [OpenAICompatibleMessage],
        maxCompletionTokens: Int,
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens,
        temperature: Double?,
        responseFormat: OpenAICompatibleResponseFormat?,
        tools: [OpenAICompatibleToolDef]?,
        toolChoice: OpenAICompatibleToolChoice?,
        reasoningEffort: String? = nil,
        stream: Bool? = nil
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
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case tools
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
        case stream
    }

    /// Coding key built at runtime, so the token cap can be written under a name chosen per vendor.
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
        // The cap goes out under the field name this vendor accepts.
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
        if let stream = stream {
            try container.encode(stream, forKey: .stream)
        }
    }
}

/// The structured-output setting sent with a request.
///
/// This client only ever sets it to `json_schema`; the wrapper alongside carries the schema itself
/// and the strict flag.
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

/// Named schema plus the strict flag, as structured outputs expect them.
///
/// The schema is held as a `WireSchema` so its keywords are emitted verbatim. Request bodies are
/// encoded with a snake_case key strategy, which would otherwise rewrite schema keywords such as
/// `additionalProperties` into names no vendor recognizes.
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
