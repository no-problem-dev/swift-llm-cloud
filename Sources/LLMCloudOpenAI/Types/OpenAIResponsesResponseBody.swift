import Foundation
import StructuredDataCore

/// Response body of the Responses API.
///
/// The same shape arrives two ways: as the body of a non-streaming call, and embedded in the
/// `response.completed` event of a stream. Where Chat Completions returns a list of choices, the
/// Responses API returns `output`, an ordered array of typed items.
package struct OpenAIResponsesResponseBody: Decodable {
    /// Id of the response. It is what a stateful caller would send as `previous_response_id`;
    /// this client never does, since it runs with `store` disabled.
    package let id: String?
    package let model: String?
    package let output: [OpenAIResponsesOutputItem]
    package let usage: OpenAIResponsesUsage?
    /// Lifecycle state: `completed`, `in_progress`, `failed`, and similar.
    package let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case output
        case usage
        case status
    }
}

// MARK: - Output Item

/// One entry of the output array, discriminated by its `type` field.
///
/// The types that are understood:
///
/// - `reasoning`: the model's internal reasoning, carried in `summary` and `content`. Reasoning
///   models emit one of these even when both are empty.
/// - `function_call`: a tool call, with the `call_id` that its result has to echo.
/// - `message`: ordinary assistant output, whose text blocks are concatenated.
///
/// Anything else decodes as unknown rather than failing, so a new item type introduced by OpenAI
/// does not break the whole response.
package enum OpenAIResponsesOutputItem: Decodable {
    case reasoning(text: String?)
    case functionCall(id: String?, callId: String, name: String, arguments: String)
    case message(text: String)
    case unknown(type: String)

    private enum TypeKey: String, CodingKey {
        case type
    }

    private enum ReasoningKeys: String, CodingKey {
        case summary
        case content
    }

    private enum FunctionCallKeys: String, CodingKey {
        case id
        case callId = "call_id"
        case name
        case arguments
    }

    private enum MessageKeys: String, CodingKey {
        case content
    }

    private enum ItemType: String {
        case reasoning
        case functionCall = "function_call"
        case message
    }

    package init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch ItemType(rawValue: type) {
        case .reasoning:
            let container = try decoder.container(keyedBy: ReasoningKeys.self)
            // `summary` arrives as an array of [{type:"summary_text", text:"..."}].
            // `content` has a similar shape, and both are often empty.
            var collected: [String] = []
            if let summary = try? container.decodeIfPresent([ReasoningTextBlock].self, forKey: .summary) {
                collected.append(contentsOf: summary.compactMap(\.text))
            }
            if let content = try? container.decodeIfPresent([ReasoningTextBlock].self, forKey: .content) {
                collected.append(contentsOf: content.compactMap(\.text))
            }
            let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            self = .reasoning(text: joined.isEmpty ? nil : joined)

        case .functionCall:
            let container = try decoder.container(keyedBy: FunctionCallKeys.self)
            let id = try container.decodeIfPresent(String.self, forKey: .id)
            let callId = try container.decode(String.self, forKey: .callId)
            let name = try container.decode(String.self, forKey: .name)
            // `arguments` is normally a JSON string. Should an object arrive instead,
            // re-encode it so callers always see a string.
            let arguments: String
            if let asString = try? container.decode(String.self, forKey: .arguments) {
                arguments = asString
            } else if let asJSON = try? container.decode(OpenAIResponsesJSONValue.self, forKey: .arguments) {
                let data = try JSONEncoder().encode(asJSON)
                arguments = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                arguments = "{}"
            }
            self = .functionCall(id: id, callId: callId, name: name, arguments: arguments)

        case .message:
            let container = try decoder.container(keyedBy: MessageKeys.self)
            let blocks = (try? container.decodeIfPresent([MessageContentBlock].self, forKey: .content)) ?? []
            let text = blocks.compactMap(\.text).joined()
            self = .message(text: text)

        case nil:
            self = .unknown(type: type)
        }
    }

    // MARK: - Nested decoding helpers

    private struct ReasoningTextBlock: Decodable {
        let text: String?
    }

    private struct MessageContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - Usage

/// Token counts OpenAI billed for a response.
///
/// Both detail blocks describe a subset of the count above them rather than an extra charge:
/// cached tokens are part of `input_tokens`, and reasoning tokens are part of `output_tokens`.
/// Adding them on top double-counts.
package struct OpenAIResponsesUsage: Decodable {
    package let inputTokens: Int?
    package let outputTokens: Int?
    package let totalTokens: Int?
    package let inputTokensDetails: InputTokensDetails?
    package let outputTokensDetails: OutputTokensDetails?

    /// Breakdown of the input count.
    package struct InputTokensDetails: Decodable {
        /// Prompt tokens served from OpenAI's automatic prompt cache, already counted in
        /// `input_tokens`.
        package let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    /// Breakdown of the output count.
    package struct OutputTokensDetails: Decodable {
        /// Tokens the model spent thinking, already counted in `output_tokens` and billed at the
        /// output rate even though they never appear in the text.
        package let reasoningTokens: Int?

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
    }
}

// MARK: - Generic JSON Value

/// Arbitrary JSON value, aliased to the shared structured-data representation.
package typealias OpenAIResponsesJSONValue = StructuredValue

// MARK: - Error response

package struct OpenAIResponsesErrorBody: Decodable {
    package let error: OpenAIResponsesError

    package struct OpenAIResponsesError: Decodable {
        package let message: String
        package let type: String?
        package let code: String?
    }
}
