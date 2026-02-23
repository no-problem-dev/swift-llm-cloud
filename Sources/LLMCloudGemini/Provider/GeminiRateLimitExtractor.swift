import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

// MARK: - Gemini Rate Limit Header Extraction

/// Gemini API のレート制限ヘッダーからレート制限情報を抽出する列挙型
///
/// `retry-after` ヘッダーを解析してリトライ待機時間を提供します。
public enum GeminiRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        let retryAfter: TimeInterval? = response
            .value(forHTTPHeaderField: "retry-after")
            .flatMap { Double($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: nil,
            requestsResetIn: nil,
            remainingTokens: nil,
            tokensResetIn: nil
        )
    }
}
