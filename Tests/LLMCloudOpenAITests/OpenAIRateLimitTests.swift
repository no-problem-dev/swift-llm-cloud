import Foundation
import Testing
import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// 共有 RateLimitHeaderExtraction(.openAICompatible) が既存抽出と一致することを検証する。
@Suite("OpenAI-compatible rate-limit extraction")
struct OpenAIRateLimitTests {
    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
    }

    @Test("Generic(.openAICompatible) は既存抽出と一致（duration suffix reset）")
    func matchesExisting() {
        let r = response([
            "retry-after": "2",
            "x-ratelimit-remaining-requests": "59",
            "x-ratelimit-reset-requests": "6m0s",
            "x-ratelimit-remaining-tokens": "150000",
            "x-ratelimit-reset-tokens": "500ms",
        ])
        let shared = RateLimitHeaderExtraction.openAICompatible.extract(from: r)
        let original = OpenAICompatibleRateLimitExtractor.extractRateLimitInfo(from: r)
        #expect(shared.retryAfter == original.retryAfter)
        #expect(shared.remainingRequests == original.remainingRequests)
        #expect(shared.requestsResetIn == original.requestsResetIn)
        #expect(shared.remainingTokens == original.remainingTokens)
        #expect(shared.tokensResetIn == original.tokensResetIn)
        #expect(shared.tokensResetIn == 0.5)  // 500ms
    }
}
