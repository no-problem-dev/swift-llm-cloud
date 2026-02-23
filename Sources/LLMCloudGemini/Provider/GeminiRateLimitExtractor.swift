import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

// MARK: - Gemini Rate Limit Header Extraction

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
