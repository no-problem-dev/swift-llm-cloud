import Foundation
import Testing
import LLMCloudClient
@testable import LLMCloudAnthropic

/// Pins which headers are read off an Anthropic 429 and how their reset values are interpreted.
///
/// Anthropic reports resets as absolute RFC 3339 timestamps, so extraction converts them into a
/// remaining duration; the assertions compare with a tolerance because that duration is measured
/// against the wall clock. ``AnthropicRateLimitExtractor`` is a thin call into the shared
/// `.anthropic` profile, so the parity check guards that wiring and the header names rather than
/// two independent implementations.
@Suite("Anthropic rate-limit extraction")
struct AnthropicRateLimitTests {
    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
    }

    @Test("Generic(.anthropic) は既存抽出と一致")
    func matchesExisting() {
        let r = response([
            "retry-after": "5",
            "anthropic-ratelimit-requests-remaining": "10",
            "anthropic-ratelimit-requests-reset": "2099-01-01T00:00:00Z",
            "anthropic-ratelimit-tokens-remaining": "1000",
            "anthropic-ratelimit-tokens-reset": "2099-01-01T00:00:00.500Z",
        ])
        let shared = RateLimitHeaderExtraction.anthropic.extract(from: r)
        let original = AnthropicRateLimitExtractor.extractRateLimitInfo(from: r)
        #expect(shared.retryAfter == original.retryAfter)
        #expect(shared.remainingRequests == original.remainingRequests)
        #expect(shared.remainingTokens == original.remainingTokens)
        #expect(abs((shared.requestsResetIn ?? -1) - (original.requestsResetIn ?? -2)) < 1.0)
        #expect(abs((shared.tokensResetIn ?? -1) - (original.tokensResetIn ?? -2)) < 1.0)
        #expect(shared.requestsResetIn != nil)
    }

    @Test("ヘッダー欠落時は nil")
    func missingHeaders() {
        let info = RateLimitHeaderExtraction.anthropic.extract(from: response([:]))
        #expect(info.retryAfter == nil)
        #expect(info.remainingRequests == nil)
        #expect(info.requestsResetIn == nil)
    }
}
