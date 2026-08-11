import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// Reads Anthropic's rate limit headers off a response for the retry layer.
///
/// The behaviour lives in the shared `.anthropic` header configuration: request and token
/// budgets under `anthropic-ratelimit-*`, whose `-reset` values are RFC 3339 timestamps rather
/// than durations and are converted to seconds from now. When `retry-after` is present it wins
/// over both resets, and any of the three beats the computed exponential backoff.
enum AnthropicRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.anthropic.extract(from: response)
    }
}
