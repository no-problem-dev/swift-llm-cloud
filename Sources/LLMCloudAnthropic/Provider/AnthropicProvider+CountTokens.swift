import APIClient
import APIContract
import Foundation
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - AnthropicProvider + count_tokens

extension AnthropicProvider {

    /// `/v1/messages/count_tokens` で system + tools + messages の入力トークン数を取得する。
    ///
    /// send パスと同一の変換器（`AnthropicMessageConverter` / `ToolSet.toAnthropicToolDefs()`）を
    /// 用いてボディを構築し、見積りと実リクエストの内容を一致させる。
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

        // file_id 参照を使う場合のみ Files API beta を付与（send と同じ判定を再利用）。
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

/// `TokenCounting` port の Anthropic adapter。`AnthropicClient.tokenCounter` から取得する。
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
