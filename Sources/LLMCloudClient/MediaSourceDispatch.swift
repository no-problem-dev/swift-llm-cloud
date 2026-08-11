import Foundation
import LLMClient

extension MediaSource {
    /// Turns an image or document source into whatever shape one provider's wire format wants.
    ///
    /// Providers accept the same three kinds of media input — inline bytes, a URL the provider
    /// fetches itself, and an id previously uploaded to the provider's Files API — but disagree
    /// on how to spell them, so each converter supplies three closures and never writes the
    /// switch. Adding a fourth source kind then breaks every converter at compile time instead
    /// of silently falling through a `default`.
    ///
    /// - Parameters:
    ///   - base64: Given the raw bytes. Providers base64-encode them here, except Anthropic,
    ///     which sends plain-text documents as UTF-8 text instead.
    ///   - url: Given the source URL, which the provider fetches server-side.
    ///   - fileReference: Given the provider-issued file id. Anthropic requires a beta header
    ///     for these; Gemini and OpenAI take them on the normal endpoint.
    public func fold<T>(
        base64: (Data) -> T,
        url: (URL) -> T,
        fileReference: (String) -> T
    ) -> T {
        switch self {
        case .base64(let data):
            return base64(data)
        case .url(let value):
            return url(value)
        case .fileReference(let id):
            return fileReference(id)
        }
    }
}
