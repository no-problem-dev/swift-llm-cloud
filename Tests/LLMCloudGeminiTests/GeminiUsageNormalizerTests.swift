import Testing
import LLMClient
@testable import LLMCloudGemini

@Suite("GeminiUsageNormalizer")
struct GeminiUsageNormalizerTests {

    @Test("promptTokenCount は cached 込み総量なのでそのまま inputTokens に入る")
    func inputIncludesCached() {
        let usage = GeminiUsageNormalizer.normalize(
            promptTokenCount: 10_000,
            candidatesTokenCount: 500,
            thoughtsTokenCount: 200,
            cachedContentTokenCount: 7_000
        )
        #expect(usage.inputTokens == 10_000)
        #expect(usage.outputTokens == 500)
        #expect(usage.reasoningTokens == 200)
        #expect(usage.cacheReadTokens == 7_000)
        #expect(usage.cacheTier == .short)
    }

    @Test("freshInputTokens = promptTokenCount - cachedContentTokenCount")
    func fresh() {
        let usage = GeminiUsageNormalizer.normalize(
            promptTokenCount: 10_000,
            candidatesTokenCount: 0,
            thoughtsTokenCount: nil,
            cachedContentTokenCount: 7_000
        )
        #expect(usage.freshInputTokens == 3_000)
    }

    @Test("candidatesTokenCount は thoughts 込みなので visibleOutput はその差")
    func visibleOutput() {
        let usage = GeminiUsageNormalizer.normalize(
            promptTokenCount: 100,
            candidatesTokenCount: 1_000,
            thoughtsTokenCount: 800,
            cachedContentTokenCount: nil
        )
        #expect(usage.visibleOutputTokens == 200)
    }

    @Test("キャッシュ無しなら cacheTier も nil")
    func noCache() {
        let usage = GeminiUsageNormalizer.normalize(
            promptTokenCount: 100,
            candidatesTokenCount: 50,
            thoughtsTokenCount: nil,
            cachedContentTokenCount: nil
        )
        #expect(usage.cacheTier == nil)
    }
}
