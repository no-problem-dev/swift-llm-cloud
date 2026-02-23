import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

// MARK: - Anthropic Rate Limit Header Extraction

public enum AnthropicRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        let retryAfter: TimeInterval? = response
            .value(forHTTPHeaderField: "retry-after")
            .flatMap { Double($0) }

        let remainingRequests = response
            .value(forHTTPHeaderField: "anthropic-ratelimit-requests-remaining")
            .flatMap { Int($0) }

        let requestsResetIn = response
            .value(forHTTPHeaderField: "anthropic-ratelimit-requests-reset")
            .flatMap { parseRFC3339ToInterval($0) }

        let remainingTokens = response
            .value(forHTTPHeaderField: "anthropic-ratelimit-tokens-remaining")
            .flatMap { Int($0) }

        let tokensResetIn = response
            .value(forHTTPHeaderField: "anthropic-ratelimit-tokens-reset")
            .flatMap { parseRFC3339ToInterval($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: remainingRequests,
            requestsResetIn: requestsResetIn,
            remainingTokens: remainingTokens,
            tokensResetIn: tokensResetIn
        )
    }

    private static func parseRFC3339ToInterval(_ value: String) -> TimeInterval? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }
}
