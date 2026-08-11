import Foundation
import LLMClient
import LLMTool

// MARK: - AnthropicClient + TokenCounting

extension AnthropicClient {

    /// Token counter backed by Anthropic's own `count_tokens` endpoint.
    ///
    /// Each count is a real request to `/v1/messages/count_tokens`, not a local estimate, so the
    /// figure matches what Anthropic would bill for the input — at the cost of a round trip that
    /// consumes request rate limit.
    ///
    /// Counting goes through the unretried provider on purpose: measurement is metering, and a
    /// caller that wants failed counts retried owns that decision rather than silently paying
    /// for extra round trips here.
    public var tokenCounter: any TokenCounting {
        AnthropicTokenCounter(provider: baseProvider)
    }
}
