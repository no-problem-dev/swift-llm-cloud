import Foundation

/// thoughtSignature をツール呼び出し ID に埋め込む/取り出すユーティリティ
///
/// Gemini API は functionCall パーツに `thoughtSignature` を返すが、
/// 汎用型 (`LLMResponse.ContentBlock.toolUse`) にはこのフィールドがない。
/// UUID で生成するツール呼び出し ID に base64 エンコードして埋め込み、
/// Gemini リクエスト再構築時にデコードして復元する。
///
/// フォーマット: `{uuid}::ts::{base64_encoded_signature}`
enum GeminiThoughtSignatureEncoding {
    private static let separator = "::ts::"

    /// thoughtSignature を含む tool call ID を生成
    static func encodeToolCallId(thoughtSignature: String?) -> String {
        let uuid = UUID().uuidString
        guard let sig = thoughtSignature,
              let data = sig.data(using: .utf8) else {
            return uuid
        }
        return uuid + separator + data.base64EncodedString()
    }

    /// tool call ID から thoughtSignature をデコード
    static func decodeThoughtSignature(from toolCallId: String) -> String? {
        guard let range = toolCallId.range(of: separator) else { return nil }
        let encoded = String(toolCallId[range.upperBound...])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
