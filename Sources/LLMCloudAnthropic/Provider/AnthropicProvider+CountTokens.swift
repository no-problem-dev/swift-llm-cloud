import APIClient
import APIContract
import Foundation
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - AnthropicProvider + count_tokens

extension AnthropicProvider {

    /// Asks Anthropic how many input tokens a system prompt, tool set, and history come to.
    ///
    /// This is a pre-flight network request to `/v1/messages/count_tokens`, tokenized by
    /// Anthropic rather than approximated locally, so the number is the billed input count and
    /// not a guess. Nothing is generated and no output count exists.
    ///
    /// The body is built with the same converters the send path uses, so what is counted is what
    /// would be sent. Failures surface as the same error types a send would raise.
    func countTokens(
        model: String,
        systemPrompt: String?,
        messages: [LLMMessage],
        tools: ToolSet?
    ) async throws -> Int {
        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0) }
        let toolDefs: [AnthropicToolDef]? = {
            guard let tools, !tools.isEmpty else { return nil }
            return tools.toAnthropicToolDefs()
        }()

        let body = AnthropicCountTokensBody(
            model: model,
            system: systemPrompt,
            messages: anthropicMessages,
            tools: toolDefs
        )

        // Same beta decision as the send path, so the count sees the request the send would make.
        let beta = Self.betaValues(for: messages)
        let endpoint = AnthropicAPI.CountTokens(beta: beta, request: body)

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)
            return apiResponse.output.inputTokens
        } catch let error as LLMError {
            throw error
        } catch let error as RateLimitAwareError {
            throw error
        } catch let error as APIError {
            throw mapAPIErrorToLLMError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }
}

// MARK: - AnthropicTokenCounter (adapter)

/// Adapts Anthropic's count_tokens endpoint to the shared token counting interface.
///
/// Obtained from the client's token counter property; the provider it holds does not retry.
struct AnthropicTokenCounter: TokenCounting {
    let provider: AnthropicProvider

    func countInputTokens(
        modelID: String,
        systemPrompt: String?,
        messages: [LLMMessage],
        tools: ToolSet?
    ) async throws -> Int {
        try await provider.countTokens(
            model: modelID,
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )
    }
}
