import LLMCloudClient
import LLMClient
import LLMTool
import Foundation

extension AnthropicClient: ToolCallableClient {
    public func planToolCalls(
        messages: [LLMMessage],
        model: ClaudeModel,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0) }
        let anthropicTools = try tools.toAnthropicFormat().map { try AnthropicToolDef(dict: $0) }

        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: maxTokens ?? Self.toolDefaultMaxTokens,
            temperature: temperature,
            tools: anthropicTools,
            toolChoice: toolChoice.map { AnthropicToolChoiceValue($0) }
        )

        let (response, _, _) = try await baseProvider.sendBody(body, beta: nil)
        return Self.parseToolCallResponse(response)
    }

    private static let toolDefaultMaxTokens = 4096

    private static func parseToolCallResponse(_ response: AnthropicResponseBody) -> ToolCallResponse {
        var toolCalls: [ToolCall] = []
        var textContent: String?

        for block in response.content {
            switch block.type {
            case "text":
                textContent = block.text
            case "tool_use":
                if let id = block.id, let name = block.name, let input = block.input,
                   let inputData = try? JSONEncoder().encode(input) {
                    toolCalls.append(ToolCall(id: id, name: name, arguments: inputData))
                }
            default:
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
