import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// Reads what little rate-limit information Gemini responses carry.
///
/// Gemini publishes no remaining-request or remaining-token headers, so `retry-after` is the only
/// signal available and backoff falls back to the retry policy whenever the server omits it. The
/// header names live in the `.gemini` case of ``RateLimitHeaderExtraction``.
enum GeminiRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.gemini.extract(from: response)
    }
}
