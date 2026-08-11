import Foundation
import LLMClient

// MARK: - AnthropicUsageRaw

/// The shape of an Anthropic usage object, independent of which response type it arrived in.
///
/// Every response variant that reports usage conforms, which is what lets one normalizer serve
/// the plain send, chat, tool-calling, and agent paths.
package protocol AnthropicUsageRaw {
    var inputTokens: Int { get }
    var outputTokens: Int { get }
    var cacheCreationInputTokens: Int? { get }
    var cacheReadInputTokens: Int? { get }
}

// MARK: - AnthropicUsageNormalizer

/// Normalizes Anthropic usage counters into the shared token-accounting shape.
///
/// Anthropic's `input_tokens` counts only the fresh part of the prompt — the part after the
/// cache breakpoint. Cache hits and cache writes come back separately as
/// `cache_read_input_tokens` and `cache_creation_input_tokens` and are excluded from it.
///
/// The shared `TokenUsage.inputTokens` contract is the opposite: total input including cached
/// tokens. Summing the three fields here is what makes an Anthropic figure comparable with an
/// OpenAI or Gemini one, which already report the cache-inclusive total.
enum AnthropicUsageNormalizer {

    /// Builds normalized usage from the raw counter fields.
    ///
    /// The cache tier cannot be inferred from a response — Anthropic does not report which TTL
    /// was used — so it is taken from the request when the caller knows it. Otherwise any cache
    /// activity is assumed to be the five-minute tier, which under-reports cost for prompts
    /// cached with the one-hour TTL.
    static func normalize(
        rawInputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int?,
        cacheReadTokens: Int?,
        cacheTier: CacheTier? = nil
    ) -> TokenUsage {
        let read = cacheReadTokens ?? 0
        let creation = cacheCreationTokens ?? 0
        let normalizedInput = rawInputTokens + read + creation

        // No explicit tier: assume the five-minute one whenever any cache counter is non-zero.
        let resolvedTier: CacheTier? = cacheTier
            ?? ((read > 0 || creation > 0) ? .short : nil)

        return TokenUsage(
            inputTokens: normalizedInput,
            outputTokens: outputTokens,
            reasoningTokens: nil,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheTier: resolvedTier
        )
    }

    /// Normalizes usage taken straight off any Anthropic response.
    package static func normalize(
        _ raw: any AnthropicUsageRaw,
        cacheTier: CacheTier? = nil
    ) -> TokenUsage {
        normalize(
            rawInputTokens: raw.inputTokens,
            outputTokens: raw.outputTokens,
            cacheCreationTokens: raw.cacheCreationInputTokens,
            cacheReadTokens: raw.cacheReadInputTokens,
            cacheTier: cacheTier
        )
    }
}
