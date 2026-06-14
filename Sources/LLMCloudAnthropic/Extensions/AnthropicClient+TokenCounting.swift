import Foundation
import LLMClient
import LLMTool

// MARK: - AnthropicClient + TokenCounting

extension AnthropicClient {

    /// コンテキストウィンドウ内訳算出（`SegmentBreakdownEngine`）に渡す `TokenCounting` port の
    /// Anthropic 実装を返す。
    ///
    /// 内部の base provider（リトライ非適用）を用いて `/v1/messages/count_tokens` を呼ぶ。
    /// 見積り計測はメータリング用途であり、リトライは内訳エンジン側の責務とする。
    public var tokenCounter: any TokenCounting {
        AnthropicTokenCounter(provider: baseProvider)
    }
}
