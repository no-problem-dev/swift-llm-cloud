import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// Reads rate-limit state off a response from an OpenAI-compatible vendor.
///
/// These vendors report on `x-ratelimit-*` headers and write reset values as durations such as
/// `250ms`, `1.5s`, or `2m` — where Anthropic sends RFC 3339 timestamps and Gemini sends nothing
/// but `retry-after`. The parsing lives in ``RateLimitHeaderExtraction``; this type exists so the
/// retry layer can name the right configuration as a type parameter.
package enum OpenAICompatibleRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.openAICompatible.extract(from: response)
    }
}
