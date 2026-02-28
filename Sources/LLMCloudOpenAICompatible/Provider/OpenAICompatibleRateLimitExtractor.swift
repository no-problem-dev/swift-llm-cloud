import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// OpenAI 互換 API のレート制限ヘッダーからレート制限情報を抽出
///
/// `retry-after`、`x-ratelimit-*` ヘッダーを解析して
/// リクエスト・トークン両方のレート制限情報を提供します。
/// OpenAI 互換プロバイダーはほぼ同じヘッダーパターンを使用。
public enum OpenAICompatibleRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        let retryAfter: TimeInterval? = response
            .value(forHTTPHeaderField: "retry-after")
            .flatMap { Double($0) }

        let remainingRequests = response
            .value(forHTTPHeaderField: "x-ratelimit-remaining-requests")
            .flatMap { Int($0) }

        let requestsResetIn = response
            .value(forHTTPHeaderField: "x-ratelimit-reset-requests")
            .flatMap { parseResetTime($0) }

        let remainingTokens = response
            .value(forHTTPHeaderField: "x-ratelimit-remaining-tokens")
            .flatMap { Int($0) }

        let tokensResetIn = response
            .value(forHTTPHeaderField: "x-ratelimit-reset-tokens")
            .flatMap { parseResetTime($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: remainingRequests,
            requestsResetIn: requestsResetIn,
            remainingTokens: remainingTokens,
            tokensResetIn: tokensResetIn
        )
    }

    private static func parseResetTime(_ value: String) -> TimeInterval? {
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
