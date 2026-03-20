import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

// MARK: - Anthropic Rate Limit Header Extraction

/// Anthropic API のレート制限ヘッダーからレート制限情報を抽出する列挙型
///
/// `retry-after`、`anthropic-ratelimit-*` ヘッダーを解析して
/// リクエスト・トークン両方のレート制限情報を提供します。
public enum AnthropicRateLimitExtractor: RateLimitInfoExtractable {
    private nonisolated(unsafe) static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
        if let date = isoFractionalFormatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        if let date = isoFormatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }
}
