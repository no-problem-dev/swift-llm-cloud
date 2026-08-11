import Foundation

/// Smuggles a thinking model's thought signature through the provider-neutral tool call id.
///
/// Gemini returns a `thoughtSignature` on the `functionCall` part of a thinking model's response,
/// and expects it echoed back with that call on the following turn; dropping it loses the model's
/// reasoning state and degrades multi-step tool use. The shared tool-use content block has no
/// field for it, but it does have an id, and Gemini itself issues no ids — so the id is free to
/// carry the signature. It is base64 encoded and appended to a UUID as `{uuid}::ts::{signature}`,
/// then decoded when the turn is converted back into a Gemini request.
///
/// A call with no signature gets a plain UUID, so ids stay unique either way.
enum GeminiThoughtSignatureEncoding {
    private static let separator = "::ts::"

    /// Mints a tool call id, embedding the signature when there is one.
    ///
    /// Each call produces a new UUID, so the result must be stored rather than recomputed.
    static func encodeToolCallId(thoughtSignature: String?) -> String {
        let uuid = UUID().uuidString
        guard let sig = thoughtSignature,
              let data = sig.data(using: .utf8) else {
            return uuid
        }
        return uuid + separator + data.base64EncodedString()
    }

    /// Recovers the thought signature from an id, or nil for an id that carries none.
    ///
    /// Ids minted by another provider simply have no separator and decode to nil.
    static func decodeThoughtSignature(from toolCallId: String) -> String? {
        guard let range = toolCallId.range(of: separator) else { return nil }
        let encoded = String(toolCallId[range.upperBound...])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
