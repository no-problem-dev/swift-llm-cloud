import Foundation

/// One `data:` frame of a streamed chat completion.
///
/// Every field except the container itself is optional, and deliberately so — the five vendors on
/// this wire format disagree about which ones they send:
///
/// - `object` is *not* decoded at all. OpenAI, xAI, and OpenRouter specify the literal
///   `chat.completion.chunk`, Mistral's spec declares a free-form string with no enum, and Groq
///   never documents the field. Gating on it would drop Mistral's stream entirely.
/// - `choices` is absent or empty on the usage-only chunk that OpenAI-style vendors send last, so
///   an empty array is a normal frame rather than a malformed one.
/// - `usage` arrives on a different frame per vendor — the last chunk for DeepSeek, every chunk for
///   xAI, always for OpenRouter — so the accumulator keeps the most recent non-`nil` value instead
///   of assuming where it lands.
package struct OpenAICompatibleStreamChunk: Decodable, Sendable {
    package let id: String?
    package let model: String?
    package let choices: [OpenAICompatibleStreamChoice]?
    package let usage: OpenAICompatibleUsage?
}

/// One alternative inside a streamed chunk.
package struct OpenAICompatibleStreamChoice: Decodable, Sendable {
    package let index: Int?
    package let delta: OpenAICompatibleStreamDelta?

    /// Why generation ended, as the vendor spells it.
    ///
    /// Left as a raw string because the vocabularies diverge: DeepSeek adds
    /// `insufficient_system_resource`, Mistral adds `model_length` and `error`, and xAI adds
    /// `end_turn`. ``OpenAICompatibleStopReasonMapper`` maps the three shared values and reports
    /// everything else as "the vendor did not say".
    package let finishReason: String?
}

/// The incremental piece of an assistant message.
package struct OpenAICompatibleStreamDelta: Decodable, Sendable {
    package let role: String?

    /// Visible text for this frame.
    package let content: OpenAICompatibleStreamText?

    /// Reasoning text under DeepSeek's and xAI's field name.
    package let reasoningContent: OpenAICompatibleStreamText?

    /// Reasoning text under OpenRouter's field name, which also accepts `reasoning_content` as an
    /// alias — hence both are decoded and whichever arrives is used.
    package let reasoning: OpenAICompatibleStreamText?

    package let toolCalls: [OpenAICompatibleStreamToolCall]?
}

/// A tool-call fragment.
///
/// Fragments are reassembled by ``index``: the first one for a call carries `id`, `type`, and
/// `function.name`, and later ones carry only more `function.arguments` text. `index` is required
/// by OpenAI, present on OpenRouter, and defaulted to 0 by Mistral, but DeepSeek does not document
/// it and Groq and xAI do not document streamed tool calls at all — so the accumulator treats it as
/// optional and falls back to position.
package struct OpenAICompatibleStreamToolCall: Decodable, Sendable {
    package let index: Int?
    package let id: String?
    package let type: String?
    package let function: OpenAICompatibleStreamToolCallFunction?
}

/// The name and argument fragment of a tool call.
package struct OpenAICompatibleStreamToolCallFunction: Decodable, Sendable {
    package let name: String?

    /// Argument text to append to what earlier fragments carried.
    ///
    /// Mistral may send this as a parsed JSON object rather than a string, so it goes through
    /// ``OpenAICompatibleStreamText``, which re-serializes an object back to its JSON text.
    package let arguments: OpenAICompatibleStreamText?
}

// MARK: - Polymorphic text

/// Text that a vendor may send as a string, as `null`, or as something structured.
///
/// Two fields on this wire format are not reliably strings. Mistral's `delta.content` can be an
/// array of content chunks rather than a string, and its `function.arguments` can be a parsed JSON
/// object rather than the JSON *text* every other vendor sends. Decoding those as `String` throws,
/// which would fail the whole frame and silently truncate the answer, so both are decoded through
/// this type instead: a string passes through, an array of content chunks has its text parts
/// joined, and anything else is re-serialized to its JSON text.
package struct OpenAICompatibleStreamText: Decodable, Sendable {
    /// The frame's contribution, flattened to text. Empty when the vendor sent `null`.
    package let value: String

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = ""
            return
        }

        if let string = try? container.decode(String.self) {
            self.value = string
            return
        }

        // Mistral's array-of-content-chunks form: keep the text parts, drop the rest.
        if let chunks = try? container.decode([ContentChunk].self) {
            self.value = chunks.compactMap(\.text).joined()
            return
        }

        // A parsed JSON object where JSON text was expected: put it back on the wire as text.
        let json = try container.decode(JSONFragment.self)
        self.value = json.serialized
    }

    private struct ContentChunk: Decodable {
        let text: String?
    }
}

// MARK: - JSON fragment

/// Any JSON value, re-serializable to compact text.
///
/// Only used to recover the JSON *text* of tool arguments a vendor chose to parse for us. Object
/// keys are written in sorted order so the same arguments always produce the same string.
private enum JSONFragment: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONFragment])
    case object([String: JSONFragment])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONFragment].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONFragment].self))
        }
    }

    var serialized: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int64(value))
                : String(value)
        case .string(let value):
            return Self.quote(value)
        case .array(let values):
            return "[" + values.map(\.serialized).joined(separator: ",") + "]"
        case .object(let values):
            let pairs = values.keys.sorted().map { "\(Self.quote($0)):\(values[$0]!.serialized)" }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    private static func quote(_ string: String) -> String {
        var out = "\""
        for character in string.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}
