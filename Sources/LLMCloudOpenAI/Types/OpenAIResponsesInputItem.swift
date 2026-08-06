import Foundation

/// `/v1/responses` の `input` 配列要素。
///
/// Responses API では、Chat Completions の `messages` とは異なり、
/// 「role 付きメッセージ」と「function_call / function_call_output 等の Item」を
/// 同一配列内に混在させる。本 enum はその union を表現する。
package enum OpenAIResponsesInputItem: Encodable, Sendable {
    /// 通常のメッセージ（user / assistant / system / developer）
    case message(role: String, content: String)

    /// テキストとメディアが混ざるメッセージ。
    ///
    /// Responses API の `content` は文字列でも配列でも受ける。画像を含むときだけ
    /// 配列にする（テキストだけのときは `.message` のまま文字列で送る — 素直で、
    /// 既存の挙動が変わらない）。
    case multipartMessage(role: String, parts: [OpenAIResponsesContentPart])

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
        case .multipartMessage(let role, let parts):
            var container = encoder.container(keyedBy: MessageKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(parts, forKey: .content)
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

// MARK: - Content Part

/// `input` のメッセージが配列で content を持つときの 1 要素。
///
/// 画像は `image_url` に **data URI か HTTP(S) URL** を入れる。OpenAI Files API に
/// 上げたものは `file_id` で参照する。
package enum OpenAIResponsesContentPart: Encodable, Sendable {
    case inputText(String)
    /// data URI（`data:image/png;base64,...`）か HTTP(S) URL
    case inputImage(url: String)
    /// OpenAI Files API のファイル ID
    case inputImageFile(fileId: String)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let url):
            try container.encode("input_image", forKey: .type)
            try container.encode(url, forKey: .imageUrl)
        case .inputImageFile(let fileId):
            try container.encode("input_image", forKey: .type)
            try container.encode(fileId, forKey: .fileId)
        }
    }

    private enum Keys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
        case fileId = "file_id"
    }
}
