import Testing
import LLMClient
@testable import LLMCloudAnthropic

@Suite("AnthropicUsageNormalizer")
struct AnthropicUsageNormalizerTests {

    @Test("Anthropic の input は fresh のみなので、cacheRead + cacheCreation を合算して正規化される")
    func normalizeInputIncludesCacheTokens() {
        let usage = AnthropicUsageNormalizer.normalize(
            rawInputTokens: 50,
            outputTokens: 200,
            cacheCreationTokens: 1_000,
            cacheReadTokens: 9_000
        )
        #expect(usage.inputTokens == 10_050)
        #expect(usage.outputTokens == 200)
        #expect(usage.cacheReadTokens == 9_000)
        #expect(usage.cacheCreationTokens == 1_000)
        #expect(usage.cacheTier == .short)  // inferred: any cache activity without an explicit tier means the 5-minute tier
    }

    @Test("cache がない場合は cacheTier も nil")
    func normalizeWithoutCache() {
        let usage = AnthropicUsageNormalizer.normalize(
            rawInputTokens: 1_000,
            outputTokens: 500,
            cacheCreationTokens: nil,
            cacheReadTokens: nil
        )
        #expect(usage.inputTokens == 1_000)
        #expect(usage.cacheTier == nil)
    }

    @Test("cacheTier の明示指定が優先される")
    func cacheTierExplicit() {
        let usage = AnthropicUsageNormalizer.normalize(
            rawInputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 100,
            cacheReadTokens: nil,
            cacheTier: .long
        )
        #expect(usage.cacheTier == .long)
    }

    @Test("freshInputTokens は正規化後の input から再計算しても合う")
    func freshAfterNormalize() {
        let usage = AnthropicUsageNormalizer.normalize(
            rawInputTokens: 100,
            outputTokens: 0,
            cacheCreationTokens: 200,
            cacheReadTokens: 700
        )
        #expect(usage.freshInputTokens == 100)
    }
}
