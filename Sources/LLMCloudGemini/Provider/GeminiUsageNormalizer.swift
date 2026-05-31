import Foundation
import LLMClient

// MARK: - GeminiUsageMetadataRaw

/// Gemini API の usageMetadata の必要フィールドを構造的に表すプロトコル。
package protocol GeminiUsageMetadataRaw {
    var promptTokenCount: Int? { get }
    var candidatesTokenCount: Int? { get }
    var thoughtsTokenCount: Int? { get }
    var cachedContentTokenCount: Int? { get }
}

// MARK: - GeminiUsageNormalizer

/// Gemini API の usageMetadata を `TokenUsage` のセマンティクス契約に変換する。
///
/// - `promptTokenCount` は cachedContentTokenCount を**含む**（公式仕様）。`inputTokens` にそのまま入れて OK。
/// - `candidatesTokenCount` は **Gemini API では thoughtsTokenCount を含む**（Vertex AI では含まない、API のみ）。
///   よって `outputTokens` にそのまま入れ、`reasoningTokens` に `thoughtsTokenCount` を入れる。
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

    /// usageMetadata が無い場合（エラー応答等）の安全な fallback。
    public static var zero: TokenUsage { .zero }
}
