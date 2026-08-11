import Foundation
import StructuredDataCore
import LLMClient

// MARK: - Request Types

/// How the stable prefix of a generateContent request is delivered.
///
/// Gemini rejects a request that carries `cachedContent` together with `systemInstruction`,
/// `tools`, or `toolConfig` with a 400: those parts were frozen when the cache was created.
/// Modelling the exclusivity as an enum makes the invalid combination unrepresentable.
enum GeminiPromptContext: Sendable {
    /// Sends the prefix in the request body itself.
    case inline(systemInstruction: GeminiContent?, tools: [GeminiTool]?, toolConfig: GeminiToolConfig?)
    /// References an existing cache resource by its `cachedContents/{id}` name.
    case cached(name: String)
}

/// Request body for `generateContent` and `streamGenerateContent`.
///
/// Encoding is hand-written because ``GeminiPromptContext`` decides which mutually exclusive
/// prefix keys appear at the top level of the JSON.
struct GeminiRequestBody: Encodable, Sendable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
    let promptContext: GeminiPromptContext

    init(
        contents: [GeminiContent],
        generationConfig: GeminiGenerationConfig,
        promptContext: GeminiPromptContext
    ) {
        self.contents = contents
        self.generationConfig = generationConfig
        self.promptContext = promptContext
    }

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig
        case systemInstruction
        case tools
        case toolConfig
        case cachedContent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contents, forKey: .contents)
        try container.encode(generationConfig, forKey: .generationConfig)
        switch promptContext {
        case .inline(let systemInstruction, let tools, let toolConfig):
            try container.encodeIfPresent(systemInstruction, forKey: .systemInstruction)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(toolConfig, forKey: .toolConfig)
        case .cached(let name):
            try container.encode(name, forKey: .cachedContent)
        }
    }
}

/// One entry of the `tools` array; Gemini groups every callable function under a single tool.
struct GeminiTool: Encodable, Sendable {
    let functionDeclarations: [GeminiFunctionDeclaration]
}

/// Declaration of one callable function, with its parameters as a Gemini-adapted JSON schema.
struct GeminiFunctionDeclaration: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: JSONSchema

    init(name: String, description: String, parameters: JSONSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Wrapper that carries the function-calling mode alongside the declared tools.
struct GeminiToolConfig: Encodable, Sendable {
    let functionCallingConfig: GeminiFunctionCallingConfig
}

/// Function-calling mode sent to Gemini.
///
/// `mode` is one of `AUTO`, `NONE`, or `ANY`. Forcing a specific tool is expressed as `ANY`
/// narrowed by `allowedFunctionNames`; Gemini has no single-tool mode of its own.
struct GeminiFunctionCallingConfig: Encodable, Sendable {
    let mode: String
    let allowedFunctionNames: [String]?
}

/// Sampling and output settings for one request.
///
/// `responseMimeType` plus `responseSchema` is how Gemini expresses structured output; both are
/// set together when a response schema is supplied.
struct GeminiGenerationConfig: Encodable, Sendable {
    var maxOutputTokens: Int
    var temperature: Double?
    var responseMimeType: String?
    var responseSchema: JSONSchema?
    var thinkingConfig: GeminiThinkingConfig?
}

/// Thinking budget for a request; exactly one of the two fields applies per model family.
///
/// Gemini 3 models take a `thinkingLevel` string, Gemini 2.5 models take an integer
/// `thinkingBudget`. Sending either to a model that does not support thinking is an API error, so
/// callers gate on the model before filling this in.
struct GeminiThinkingConfig: Encodable, Sendable {
    var thinkingLevel: String?
    var thinkingBudget: Int?
}

// MARK: - Content Types

/// One turn of the conversation: a role plus its parts.
///
/// The role is `user` or `model`. Decoding tolerates a turn with no `parts` at all, which Gemini
/// can return when a candidate is cut short, and yields an empty array rather than failing.
struct GeminiContent: Codable, Sendable {
    let role: String
    let parts: [GeminiPart]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        parts = (try? container.decodeIfPresent([GeminiPart].self, forKey: .parts)) ?? []
    }

    init(role: String, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

/// A single piece of a turn: text, a function call, a function result, or media.
///
/// Gemini models the whole payload as one shape with every field optional, and exactly one is
/// populated per part. `thoughtSignature` rides along on a `functionCall` from a thinking model
/// and has to be echoed back on the next turn or the model loses its reasoning state.
struct GeminiPart: Codable, Sendable {
    let text: String?
    let functionCall: GeminiFunctionCall?
    let functionResponse: GeminiFunctionResponse?
    let inlineData: GeminiInlineData?
    let fileData: GeminiFileData?
    let thoughtSignature: String?

    init(text: String) {
        self.text = text
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiFunctionCall) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(functionCall: GeminiFunctionCall, thoughtSignature: String?) {
        self.text = nil
        self.functionCall = functionCall
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = thoughtSignature
    }

    init(functionResponse: GeminiFunctionResponse) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = functionResponse
        self.inlineData = nil
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(inlineData: GeminiInlineData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = inlineData
        self.fileData = nil
        self.thoughtSignature = nil
    }

    init(fileData: GeminiFileData) {
        self.text = nil
        self.functionCall = nil
        self.functionResponse = nil
        self.inlineData = nil
        self.fileData = fileData
        self.thoughtSignature = nil
    }
}

/// Media carried in the request body itself, base64 encoded.
///
/// Suits small attachments; anything large should be uploaded through the File API and referenced
/// with ``GeminiFileData`` instead. These two keys are snake_case even though the rest of the
/// Gemini wire format is camelCase.
struct GeminiInlineData: Codable, Sendable {
    let mimeType: String
    let data: String  // Base64-encoded bytes.

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

/// Reference to media already uploaded through the Gemini File API, or a reachable URL.
///
/// Like ``GeminiInlineData``, these keys are snake_case on the wire.
struct GeminiFileData: Codable, Sendable {
    let mimeType: String
    let fileUri: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case fileUri = "file_uri"
    }
}

/// A tool call the model wants performed, named and with arguments already parsed.
///
/// Unlike OpenAI and Anthropic, Gemini attaches no call id and streams no partial arguments: a
/// `functionCall` arrives complete inside a single chunk, and a result is matched back to it by
/// function name alone.
struct GeminiFunctionCall: Codable, Sendable {
    let name: String
    let args: GeminiJSONValue?

    init(name: String, args: GeminiJSONValue?) {
        self.name = name
        self.args = args
    }
}

/// The result of running a tool, sent back to the model.
///
/// The `name` must match the `functionCall` being answered, since Gemini has no call ids to pair
/// them with. Results belong to a `user` turn.
struct GeminiFunctionResponse: Codable, Sendable {
    let name: String
    let response: GeminiJSONValue

    init(name: String, response: GeminiJSONValue) {
        self.name = name
        self.response = response
    }
}

// MARK: - Response Types

/// Response body of `generateContent`, and of each SSE chunk of `streamGenerateContent`.
///
/// A streamed chunk uses this same shape rather than a delta shape: partial text arrives as a new
/// candidate part, and `usageMetadata` repeats a running total instead of an increment.
/// `candidates` is empty when the prompt itself was blocked, in which case `promptFeedback`
/// carries the reason.
struct GeminiResponseBody: Decodable, Sendable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
    let usageMetadata: GeminiUsageMetadata?
}

/// One generated alternative; only the first is used here.
///
/// `finishReason` is present on the final chunk of a stream and absent on the earlier ones.
struct GeminiCandidate: Decodable, Sendable {
    let content: GeminiContent?
    let finishReason: String?
    let safetyRatings: [GeminiSafetyRating]?
}

/// Safety verdict on the prompt, populated when Gemini refused to generate anything.
struct GeminiPromptFeedback: Decodable, Sendable {
    let blockReason: String?
    let safetyRatings: [GeminiSafetyRating]?
}

/// Per-category safety score attached to a prompt or a candidate.
struct GeminiSafetyRating: Decodable, Sendable {
    let category: String
    let probability: String
}

/// Raw token counters as Gemini reports them.
///
/// The counts overlap: `promptTokenCount` already includes `cachedContentTokenCount`, and on the
/// Gemini API `candidatesTokenCount` already includes `thoughtsTokenCount`. Summing the fields
/// double-counts. Use ``GeminiUsageNormalizer`` to map them onto the shared token-accounting
/// shape.
struct GeminiUsageMetadata: Decodable, Sendable, GeminiUsageMetadataRaw {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?
}

/// Envelope Gemini wraps every non-2xx body in.
struct GeminiErrorResponse: Decodable, Sendable {
    let error: GeminiErrorDetail
}

/// Error payload; `message` is the only place cache-specific failures are distinguishable.
struct GeminiErrorDetail: Decodable, Sendable {
    let code: Int
    let message: String
    let status: String
}

/// The Gemini finish reasons that map onto a shared stop reason.
///
/// A safety stop, and any reason not listed here, map to `nil`: the caller sees a response that
/// simply ended, so blocked content is reported through `promptFeedback` instead.
enum GeminiFinishReason: String {
    case stop = "STOP"
    case maxTokens = "MAX_TOKENS"
    case safety = "SAFETY"

    static func stopReason(_ raw: String?) -> LLMResponse.StopReason? {
        switch raw.flatMap(Self.init) {
        case .stop: return .endTurn
        case .maxTokens: return .maxTokens
        case .safety, nil: return nil
        }
    }
}

// MARK: - JSON Helper Types

/// Untyped JSON, used for tool-call arguments and tool results whose shape is only known at runtime.
typealias GeminiJSONValue = StructuredValue
