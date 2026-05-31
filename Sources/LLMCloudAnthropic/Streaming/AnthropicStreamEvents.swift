import Foundation
import StructuredDataCore
import JSONParsing

/// Anthropic のコンテンツブロック種別。ストリーミング/非ストリーミング双方で共有。
enum AnthropicBlockType: String {
    case thinking
    case text
    case toolUse = "tool_use"
}

enum AnthropicSSE {
    enum EventName: String {
        case messageStart = "message_start"
        case contentBlockStart = "content_block_start"
        case contentBlockDelta = "content_block_delta"
        case contentBlockStop = "content_block_stop"
        case messageDelta = "message_delta"
        case messageStop = "message_stop"
        case error
    }

    enum DeltaType: String {
        case thinkingDelta = "thinking_delta"
        case signatureDelta = "signature_delta"
        case textDelta = "text_delta"
        case inputJsonDelta = "input_json_delta"
    }

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

    struct ContentBlockStart: Decodable {
        struct Block: Decodable {
            var type: String
            var id: String?
            var name: String?
        }
        var contentBlock: Block
    }

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

    struct MessageDelta: Decodable {
        struct Delta: Decodable { var stopReason: String? }
        struct Usage: Decodable { var outputTokens: Int? }
        var delta: Delta?
        var usage: Usage?
    }

    struct ErrorEvent: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail
    }

    struct TextDelta: Decodable {
        struct Delta: Decodable { var text: String? }
        var type: String?
        var delta: Delta?
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: String) -> T? {
        guard let value = try? JSONParser().parse(data) else { return nil }
        return try? value.decode(type, options: DecodingOptions(keyStrategy: .convertFromSnakeCase))
    }
}
