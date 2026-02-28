import Foundation

/// OpenAI 互換使用量
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
