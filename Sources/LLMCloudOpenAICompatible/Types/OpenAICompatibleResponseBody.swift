import Foundation

/// Body of a completed, non-streaming chat completion.
package struct OpenAICompatibleResponseBody: Decodable, Sendable {
    package let id: String
    package let object: String
    package let created: Int
    package let model: String

    /// The alternatives the model produced; the converters read only the first.
    package let choices: [OpenAICompatibleChoice]

    /// Token counts, required rather than optional: a vendor that answers without a usage object
    /// fails to decode instead of yielding a response with unknown token counts.
    package let usage: OpenAICompatibleUsage
}

/// One alternative completion.
package struct OpenAICompatibleChoice: Decodable, Sendable {
    package let index: Int
    package let message: OpenAICompatibleResponseMessage

    /// Why generation ended, as the vendor spells it. Values outside the three shared ones become
    /// an unknown stop reason rather than an error.
    package let finishReason: String?
}

/// The assistant message inside a choice.
package struct OpenAICompatibleResponseMessage: Decodable, Sendable {
    package let role: String

    /// Absent when the model answered purely with tool calls.
    package let content: String?

    package let toolCalls: [OpenAICompatibleResponseToolCall]?
}

/// The tool-call kinds this client understands.
///
/// The wire field is decoded as a plain string and matched against this enum afterwards, so an
/// unfamiliar kind cannot break decoding of the whole response. The trade-off is silent loss: a
/// tool call of any other kind is dropped during conversion and never reaches the caller.
package enum OpenAICompatibleToolCallType: String {
    case function
}

/// A tool call requested by the model.
package struct OpenAICompatibleResponseToolCall: Decodable, Sendable {
    /// Echoed back on the tool result message that answers this call.
    package let id: String

    package let type: String
    package let function: OpenAICompatibleResponseToolCallFunction
}

/// The function name and arguments of a tool call.
package struct OpenAICompatibleResponseToolCallFunction: Decodable, Sendable {
    package let name: String

    /// Arguments as a JSON string, not a JSON object — the vendor sends the model's raw output
    /// here, so it can be malformed JSON and is only parsed by whoever runs the tool.
    package let arguments: String
}
