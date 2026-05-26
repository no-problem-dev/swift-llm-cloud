import Foundation

/// `/v1/responses` の `input` 配列要素。
///
/// Responses API では、Chat Completions の `messages` とは異なり、
/// 「role 付きメッセージ」と「function_call / function_call_output 等の Item」を
/// 同一配列内に混在させる。本 enum はその union を表現する。
package enum OpenAIResponsesInputItem: Encodable, Sendable {
    /// 通常のメッセージ（user / assistant / system / developer）
    case message(role: String, content: String)

    /// アシスタントが過去に発行した function call
    /// - Parameters:
    ///   - callId: ツール実行結果と紐付けるための ID
    ///   - name: ツール名
    ///   - arguments: JSON 文字列形式の引数（Responses API は JSON string）
    case functionCall(callId: String, name: String, arguments: String)

    /// ツール実行結果
    /// - Parameters:
    ///   - callId: `function_call.call_id` と一致させる
    ///   - output: 結果文字列（ツールが JSON を返す場合も文字列でラップ）
    case functionCallOutput(callId: String, output: String)

    package func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let role, let content):
            var container = encoder.container(keyedBy: MessageKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case .functionCall(let callId, let name, let arguments):
            var container = encoder.container(keyedBy: FunctionCallKeys.self)
            try container.encode("function_call", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionCallOutput(let callId, let output):
            var container = encoder.container(keyedBy: FunctionCallOutputKeys.self)
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(output, forKey: .output)
        }
    }

    private enum MessageKeys: String, CodingKey {
        case role
        case content
    }

    private enum FunctionCallKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case name
        case arguments
    }

    private enum FunctionCallOutputKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }
}
