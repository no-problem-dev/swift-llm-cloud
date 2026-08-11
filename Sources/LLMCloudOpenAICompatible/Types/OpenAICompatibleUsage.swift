import Foundation

/// Token counts a vendor reports alongside a chat completion.
///
/// The prompt count is the billed input total and already contains any cached prefix, so the cached
/// figure inside the prompt details is a breakdown of that total rather than an amount to add to
/// it — the opposite of Anthropic, which reports cache reads as a separate bucket. Both detail
/// objects are optional and often missing: vendors without prompt caching omit the prompt details,
/// and models that do not reason omit the completion details, so a `nil` there means "not
/// reported", never zero.
package struct OpenAICompatibleUsage: Decodable, Sendable {
    package let promptTokens: Int
    package let completionTokens: Int
    package let totalTokens: Int
    package let promptTokensDetails: PromptTokensDetails?
    package let completionTokensDetails: CompletionTokensDetails?

    package struct PromptTokensDetails: Decodable, Sendable {
        package let cachedTokens: Int?
    }

    package struct CompletionTokensDetails: Decodable, Sendable {
        package let reasoningTokens: Int?
    }
}
