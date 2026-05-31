import Foundation
import LLMClient

// MARK: - AnthropicUsageRaw

/// Anthropic API の usage オブジェクトを構造的に表す軽量プロトコル。
///
/// AnthropicUsage / AnthropicChatUsage / AnthropicToolUsage / AnthropicAgentUsage が準拠する。
package protocol AnthropicUsageRaw {
    var inputTokens: Int { get }
    var outputTokens: Int { get }
    var cacheCreationInputTokens: Int? { get }
    var cacheReadInputTokens: Int? { get }
}

// MARK: - AnthropicUsageNormalizer

/// Anthropic API レスポンスの usage を `TokenUsage` のセマンティクス契約に正規化する。
///
/// Anthropic の `input_tokens` は **キャッシュ breakpoint より後の fresh 分のみ** を表す。
/// `cache_read_input_tokens` / `cache_creation_input_tokens` は別建てで返る。
///
/// 一方 `TokenUsage.inputTokens` の契約は **キャッシュ込みの総入力トークン数** なので、
/// ここで合算して正規化する。
enum AnthropicUsageNormalizer {

    /// 生フィールドから正規化済み `TokenUsage` を構築。
    /// `cacheTier` はリクエスト時の TTL 指定に基づくため、必要なら呼び出し側で別途指定する。
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

        // tier の自動推定: 明示指定がなければ cache が使われていれば .short と仮定。
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

    /// AnthropicUsageRaw 準拠の usage から正規化。
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
