import LLMCloudClient
import LLMClient
import LLMTool
import Foundation

extension AnthropicClient: ToolCallableClient {
    /// Asks the model which tools to call, without executing any of them.
    ///
    /// Anthropic may answer with text, tool calls, or both in one turn, so the result carries
    /// both. Each call keeps the `tool_use` id Anthropic assigned it; a later turn has to echo
    /// that id back as the `tool_use_id` of its result, or the conversation is rejected. Tool
    /// arguments arrive as raw JSON bytes, and a call whose arguments fail to re-encode is
    /// dropped from the result rather than failing the turn.
    ///
    /// This path performs no retry, and it does not request extended thinking.
    public func planToolCalls(
        messages: [LLMMessage],
        model: ClaudeModel,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0) }
        let anthropicTools = tools.toAnthropicToolDefs()

        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: maxTokens ?? Self.toolDefaultMaxTokens,
            temperature: temperature,
            tools: anthropicTools,
            toolChoice: toolChoice.map { AnthropicToolChoiceValue($0) },
            cachePolicy: cachePolicy
        )

        let (response, _, _) = try await baseProvider.sendBody(body, beta: AnthropicProvider.betaValues(for: messages) + body.cacheBetaValues)
        return Self.parseToolCallResponse(response)
    }

    private static let toolDefaultMaxTokens = 4096

    /// Splits a reply into its tool calls and its text.
    ///
    /// Thinking blocks are discarded here, so reasoning cannot be replayed from this path. If a
    /// reply somehow contains several text blocks, only the last one survives.
    private static func parseToolCallResponse(_ response: AnthropicResponseBody) -> ToolCallResponse {
        var toolCalls: [ToolCall] = []
        var textContent: String?

        for block in response.content {
            switch AnthropicBlockType(rawValue: block.type) {
            case .text:
                textContent = block.text
            case .toolUse:
                if let id = block.id, let name = block.name, let input = block.input,
                   let inputData = try? JSONEncoder().encode(input) {
                    toolCalls.append(ToolCall(id: id, name: name, arguments: inputData))
                }
            case .thinking, nil:
                break
            }
        }

        return ToolCallResponse(
            toolCalls: toolCalls,
            text: textContent,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) },
            model: response.model
        )
    }
}
