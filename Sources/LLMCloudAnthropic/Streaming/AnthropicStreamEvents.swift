import Foundation
import StructuredDataCore
import JSONParsing

/// Kinds of content block Anthropic can return, shared by the streaming and single-shot paths.
///
/// An unrecognized value decodes to `nil` rather than failing, so a block type introduced later
/// is skipped instead of breaking the response.
enum AnthropicBlockType: String {
    case thinking
    case text
    case toolUse = "tool_use"
}

/// Decoders for the server-sent events of a streamed Anthropic message.
///
/// A stream runs `message_start`, then a `content_block_start` / `content_block_delta`* /
/// `content_block_stop` group per block, then `message_delta` and `message_stop`. Usage is split
/// across two events: `message_start` carries the input and cache counters, `message_delta`
/// carries the final output count. An `error` event can arrive at any point and ends the stream.
enum AnthropicSSE {
    /// Names carried in the event line of the stream.
    enum EventName: String {
        case messageStart = "message_start"
        case contentBlockStart = "content_block_start"
        case contentBlockDelta = "content_block_delta"
        case contentBlockStop = "content_block_stop"
        case messageDelta = "message_delta"
        case messageStop = "message_stop"
        case error
    }

    /// Kinds of incremental payload a content block delta can carry.
    ///
    /// The delta's own `type` field selects which one applies, and each kind puts its payload
    /// under a different key, so a consumer that reads only `text` silently ignores the other
    /// three. Tool arguments arrive as `input_json_delta` fragments that are pieces of a JSON
    /// document, not JSON documents themselves — they parse only once concatenated across the
    /// whole block. Thinking prose and its signature stream separately.
    enum DeltaType: String {
        case thinkingDelta = "thinking_delta"
        case signatureDelta = "signature_delta"
        case textDelta = "text_delta"
        case inputJsonDelta = "input_json_delta"
    }

    /// First event of the stream, carrying the model and the input side of the usage counters.
    ///
    /// The output count here is the count so far, effectively zero; the real one comes on
    /// `message_delta`. Cache counters appear only here, so a consumer that ignores this event
    /// loses all cache accounting.
    struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var inputTokens: Int?
                var outputTokens: Int?
                var cacheCreationInputTokens: Int?
                var cacheReadInputTokens: Int?
            }
            var model: String?
            var usage: Usage?
        }
        var message: Message
    }

    /// Opens a content block; for a tool use this is the only place its id and name appear.
    ///
    /// The deltas that follow carry no identity of their own, so the id and name have to be held
    /// until `content_block_stop` closes the block.
    struct ContentBlockStart: Decodable {
        struct Block: Decodable {
            var type: String
            var id: String?
            var name: String?
        }
        var contentBlock: Block
    }

    /// One increment of the block currently open, with exactly one payload field set.
    ///
    /// Which field that is follows the delta's `type`: `text` for text, `thinking` and
    /// `signature` for reasoning, and `partialJson` for tool arguments.
    struct ContentBlockDelta: Decodable {
        struct Delta: Decodable {
            var type: String?
            var thinking: String?
            var signature: String?
            var text: String?
            var partialJson: String?
        }
        var delta: Delta
    }

    /// Closes the message with the stop reason and the final output token count.
    ///
    /// This is the only event carrying the billed output total, and it repeats none of the input
    /// or cache counters from `message_start`. A stream that is cut before it arrives leaves the
    /// output count at whatever was seen so far.
    struct MessageDelta: Decodable {
        struct Delta: Decodable { var stopReason: String? }
        struct Usage: Decodable { var outputTokens: Int? }
        var delta: Delta?
        var usage: Usage?
    }

    /// Mid-stream failure reported inside the stream body, with HTTP 200 already sent.
    ///
    /// There is no status code to map, so a consumer has to invent one when converting this to
    /// an error.
    struct ErrorEvent: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail
    }

    /// Narrow view of a delta event for consumers that only want assistant text.
    ///
    /// It reads the event kind from the `type` field inside the payload rather than the SSE
    /// `event:` line, and yields nothing for thinking or tool-argument deltas, whose payloads
    /// live under other keys.
    struct TextDelta: Decodable {
        struct Delta: Decodable { var text: String? }
        var type: String?
        var delta: Delta?
    }

    /// Decodes one event payload, returning `nil` instead of throwing on malformed input.
    ///
    /// Failing soft is deliberate: an event shape this client does not model must not abort a
    /// stream that is otherwise fine. The cost is that a genuinely broken payload is dropped
    /// silently.
    static func decode<T: Decodable>(_ type: T.Type, from data: String) -> T? {
        guard let value = try? JSONParser().parse(data) else { return nil }
        return try? value.decode(type, options: DecodingOptions(keyStrategy: .convertFromSnakeCase))
    }
}
