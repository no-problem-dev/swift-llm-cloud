import Foundation
import LLMClient

// MARK: - GeminiUsageMetadataRaw

/// Structural view of the Gemini usage counters, so one normalizer serves several response types.
package protocol GeminiUsageMetadataRaw {
    var promptTokenCount: Int? { get }
    var candidatesTokenCount: Int? { get }
    var thoughtsTokenCount: Int? { get }
    var cachedContentTokenCount: Int? { get }
}

// MARK: - GeminiUsageNormalizer

/// Maps Gemini's usage counters onto the shared token-accounting contract.
///
/// Gemini's counters already nest, so the fields are copied across rather than added up:
/// - `promptTokenCount` includes `cachedContentTokenCount`, so it becomes `inputTokens` as it
///   stands and the cached figure is reported separately as a read, never subtracted.
/// - `candidatesTokenCount` includes `thoughtsTokenCount` on the Gemini API, though not on Vertex
///   AI, so it becomes `outputTokens` as it stands and thinking tokens are surfaced alongside it
///   as `reasoningTokens`.
///
/// Any cache hit is reported at the short-lived tier, since explicit `cachedContents` is the only
/// caching this client creates. Gemini reports no cache-write counter, so cache creation cost is
/// invisible here.
enum GeminiUsageNormalizer {

    static func normalize(
        promptTokenCount: Int?,
        candidatesTokenCount: Int?,
        thoughtsTokenCount: Int?,
        cachedContentTokenCount: Int?
    ) -> TokenUsage {
        let cached = cachedContentTokenCount
        return TokenUsage(
            inputTokens: promptTokenCount ?? 0,
            outputTokens: candidatesTokenCount ?? 0,
            reasoningTokens: thoughtsTokenCount,
            cacheReadTokens: cached,
            cacheCreationTokens: nil,
            cacheTier: (cached ?? 0) > 0 ? .short : nil
        )
    }

    package static func normalize(_ raw: any GeminiUsageMetadataRaw) -> TokenUsage {
        normalize(
            promptTokenCount: raw.promptTokenCount,
            candidatesTokenCount: raw.candidatesTokenCount,
            thoughtsTokenCount: raw.thoughtsTokenCount,
            cachedContentTokenCount: raw.cachedContentTokenCount
        )
    }

    /// Stand-in for a response that carried no usage metadata, such as an error reply.
    public static var zero: TokenUsage { .zero }
}
