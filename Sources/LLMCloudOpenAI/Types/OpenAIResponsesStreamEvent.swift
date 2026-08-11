import Foundation

/// A named SSE event from the Responses API, reduced to what this client acts on.
///
/// How the wire is actually read, matching what the official SDKs do:
///
/// - The `event:` line is ignored. The `data:` JSON is decoded and dispatched on its `type`
///   field, which carries the same name.
/// - The stream ends at `response.completed`, `response.failed`, or `response.incomplete`. The
///   `[DONE]` sentinel is not relied on and is discarded if it arrives.
/// - Deltas exist to be displayed as they arrive. The authoritative result is the complete
///   Response — output items, usage, status — carried by `response.completed`.
///
/// Every other event, including `response.output_item.added`, `response.content_part.added`, and
/// `response.function_call_arguments.delta`, is discarded. Tool-call arguments in particular are
/// taken from the finished Response rather than accumulated from their deltas.
package enum OpenAIResponsesStreamEvent {
    /// A chunk of visible text, from `response.output_text.delta`.
    case outputTextDelta(String)
    /// A chunk of reasoning text, from `response.reasoning_text.delta` or its summary variant
    /// `response.reasoning_summary_text.delta`.
    case reasoningTextDelta(String)
    /// The finished response, from `response.completed`, which embeds the full Response object.
    case completed(OpenAIResponsesResponseBody)
    /// A terminal failure, from `response.failed`, `response.incomplete`, or a bare `error`
    /// event. An incomplete response reports why it stopped, typically a token cap.
    case failed(message: String)
    /// An event this client does not act on, or the `[DONE]` sentinel.
    case ignored

    /// Classifies the payload of one SSE `data:` line.
    ///
    /// A payload that does not decode as JSON, or whose `type` is not one of the handled names,
    /// becomes ``ignored`` rather than an error: an unfamiliar event must not abort a stream that
    /// is otherwise proceeding normally.
    package init(data: String) {
        guard data != "[DONE]" else {
            self = .ignored
            return
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8)) else {
            self = .ignored
            return
        }
        switch payload.type {
        case "response.output_text.delta":
            self = payload.delta.map { .outputTextDelta($0) } ?? .ignored
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            self = payload.delta.map { .reasoningTextDelta($0) } ?? .ignored
        case "response.completed":
            self = payload.response.map { .completed($0.body) } ?? .ignored
        case "response.failed":
            self = .failed(message: payload.response?.errorMessage ?? "Response failed")
        case "response.incomplete":
            self = .failed(message: payload.response?.incompleteReason.map { "Response incomplete: \($0)" }
                ?? "Response incomplete")
        case "error":
            self = .failed(message: payload.message ?? "Unknown streaming error")
        default:
            self = .ignored
        }
    }

    /// The decoded `data:` JSON. Every field but `type` is optional, because each event name
    /// populates a different subset of them.
    private struct Payload: Decodable {
        let type: String
        let delta: String?
        let message: String?
        let response: ResponseEnvelope?
    }

    /// The `response` field of a lifecycle event.
    ///
    /// The same object serves both endings: on completion it is read as the full Response, and on
    /// failure as the carrier of the error message or the reason the response was cut short.
    package struct ResponseEnvelope: Decodable {
        package let body: OpenAIResponsesResponseBody
        package let errorMessage: String?
        package let incompleteReason: String?

        private enum CodingKeys: String, CodingKey {
            case error
            case incompleteDetails = "incomplete_details"
        }

        private struct ErrorInfo: Decodable {
            let message: String?
        }

        private struct IncompleteDetails: Decodable {
            let reason: String?
        }

        package init(from decoder: Decoder) throws {
            body = try OpenAIResponsesResponseBody(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            errorMessage = (try? container.decodeIfPresent(ErrorInfo.self, forKey: .error))??.message
            incompleteReason = (try? container.decodeIfPresent(IncompleteDetails.self, forKey: .incompleteDetails))??.reason
        }
    }
}
