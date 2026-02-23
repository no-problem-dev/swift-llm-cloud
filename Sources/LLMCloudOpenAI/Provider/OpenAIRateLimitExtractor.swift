import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

// MARK: - OpenAI Rate Limit Header Extraction

/// OpenAI API のレート制限ヘッダーからレート制限情報を抽出する列挙型
///
/// `retry-after`、`x-ratelimit-*` ヘッダーを解析して
/// リクエスト・トークン両方のレート制限情報を提供します。
public enum OpenAIRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        let retryAfter: TimeInterval? = response
            .value(forHTTPHeaderField: "retry-after")
            .flatMap { Double($0) }

        let remainingRequests = response
            .value(forHTTPHeaderField: "x-ratelimit-remaining-requests")
            .flatMap { Int($0) }

        let requestsResetIn = response
            .value(forHTTPHeaderField: "x-ratelimit-reset-requests")
            .flatMap { parseOpenAIResetTime($0) }

        let remainingTokens = response
            .value(forHTTPHeaderField: "x-ratelimit-remaining-tokens")
            .flatMap { Int($0) }

        let tokensResetIn = response
            .value(forHTTPHeaderField: "x-ratelimit-reset-tokens")
            .flatMap { parseOpenAIResetTime($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: remainingRequests,
            requestsResetIn: requestsResetIn,
            remainingTokens: remainingTokens,
            tokensResetIn: tokensResetIn
        )
    }

    private static func parseOpenAIResetTime(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix("ms") {
            return Double(trimmed.dropLast(2)).map { $0 / 1000 }
        } else if trimmed.hasSuffix("s") {
            return Double(trimmed.dropLast(1))
        } else if trimmed.hasSuffix("m") {
            return Double(trimmed.dropLast(1)).map { $0 * 60 }
        } else if trimmed.hasSuffix("h") {
            return Double(trimmed.dropLast(1)).map { $0 * 3600 }
        }
        return Double(trimmed)
    }
}
