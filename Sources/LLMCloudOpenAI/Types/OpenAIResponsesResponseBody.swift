import Foundation

/// `/v1/responses` のレスポンスボディ。
package struct OpenAIResponsesResponseBody: Decodable {
    package let id: String?
    package let model: String?
    package let output: [OpenAIResponsesOutputItem]
    package let usage: OpenAIResponsesUsage?
    /// `completed` / `in_progress` / `failed` 等
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

/// 出力アイテムの discriminated union。
///
/// 既知の `type` は次の通り:
/// - `reasoning`: 内部推論ブロック（content / summary を持つ）。LLMResponse へは `.thinking` にマップ。
/// - `function_call`: ツール呼び出し。
/// - `message`: 通常のアシスタントメッセージ。content[].text を集約する。
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

    package init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "reasoning":
            let container = try decoder.container(keyedBy: ReasoningKeys.self)
            // summary は配列 [{type:"summary_text", text:"..."}] になり得る。
            // content も似た形だが、空配列もよくある。
            var collected: [String] = []
            if let summary = try? container.decodeIfPresent([ReasoningTextBlock].self, forKey: .summary) {
                collected.append(contentsOf: summary.compactMap(\.text))
            }
            if let content = try? container.decodeIfPresent([ReasoningTextBlock].self, forKey: .content) {
                collected.append(contentsOf: content.compactMap(\.text))
            }
            let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            self = .reasoning(text: joined.isEmpty ? nil : joined)

        case "function_call":
            let container = try decoder.container(keyedBy: FunctionCallKeys.self)
            let id = try container.decodeIfPresent(String.self, forKey: .id)
            let callId = try container.decode(String.self, forKey: .callId)
            let name = try container.decode(String.self, forKey: .name)
            // arguments は通常 JSON string。万一 object で返ってきたら再エンコードする。
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

        case "message":
            let container = try decoder.container(keyedBy: MessageKeys.self)
            let blocks = (try? container.decodeIfPresent([MessageContentBlock].self, forKey: .content)) ?? []
            let text = blocks.compactMap(\.text).joined()
            self = .message(text: text)

        default:
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

package struct OpenAIResponsesUsage: Decodable {
    package let inputTokens: Int?
    package let outputTokens: Int?
    package let totalTokens: Int?
    package let inputTokensDetails: InputTokensDetails?
    package let outputTokensDetails: OutputTokensDetails?

    package struct InputTokensDetails: Decodable {
        package let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    package struct OutputTokensDetails: Decodable {
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

/// 任意の JSON 値を再エンコード可能な形で保持する。
package enum OpenAIResponsesJSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([OpenAIResponsesJSONValue])
    case object([String: OpenAIResponsesJSONValue])

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([OpenAIResponsesJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: OpenAIResponsesJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSON value"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - Error response

package struct OpenAIResponsesErrorBody: Decodable {
    package let error: OpenAIResponsesError

    package struct OpenAIResponsesError: Decodable {
        package let message: String
        package let type: String?
        package let code: String?
    }
}
