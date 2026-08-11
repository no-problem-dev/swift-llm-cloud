import Foundation
import Testing
import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// Pins which headers are read off an OpenAI-compatible 429 and how their reset values are parsed.
///
/// Unlike Anthropic, these vendors report resets as Go-style duration strings such as `6m0s` and
/// `500ms`, so suffix handling is where this regresses: `500ms` has to come back as 0.5 seconds,
/// not 500. ``OpenAICompatibleRateLimitExtractor`` is a thin call into the shared
/// `.openAICompatible` profile, so the parity check guards that wiring rather than two independent
/// implementations.
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
