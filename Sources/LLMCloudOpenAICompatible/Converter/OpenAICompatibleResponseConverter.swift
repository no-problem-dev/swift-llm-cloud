import Foundation
import LLMClient
import LLMTool
import LLMChat

/// OpenAI 互換レスポンス → 各種レスポンス型への変換
package enum OpenAICompatibleResponseConverter {

    /// OpenAI 互換レスポンスを LLMResponse に変換
    package static func toLLMResponse(_ response: OpenAICompatibleResponseBody) -> LLMResponse {
        guard let choice = response.choices.first else {
            return LLMResponse(
                content: [],
                model: response.model,
                usage: toTokenUsage(response.usage),
                stopReason: nil
            )
        }

        var contentBlocks: [LLMResponse.ContentBlock] = []

        if let content = choice.message.content {
            contentBlocks.append(.text(content))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                if OpenAICompatibleToolCallType(rawValue: toolCall.type) == .function,
                   let argumentsData = toolCall.function.arguments.data(using: .utf8) {
                    contentBlocks.append(.toolUse(
                        id: toolCall.id,
                        name: toolCall.function.name,
                        input: argumentsData
                    ))
                }
            }
        }

        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: toTokenUsage(response.usage),
            stopReason: OpenAICompatibleStopReasonMapper.map(choice.finishReason)
        )
    }

    /// OpenAI 互換レスポンスを ToolCallResponse に変換
    package static func toToolCallResponse(_ response: OpenAICompatibleResponseBody) -> ToolCallResponse {
        guard let choice = response.choices.first else {
            return ToolCallResponse(
                toolCalls: [],
                text: nil,
                usage: toTokenUsage(response.usage),
                stopReason: nil,
                model: response.model
            )
        }

        var toolCalls: [ToolCall] = []

        if let responseToolCalls = choice.message.toolCalls {
            for toolCall in responseToolCalls {
                if OpenAICompatibleToolCallType(rawValue: toolCall.type) == .function,
                   let argumentsData = toolCall.function.arguments.data(using: .utf8) {
                    toolCalls.append(ToolCall(
                        id: toolCall.id,
                        name: toolCall.function.name,
                        arguments: argumentsData
                    ))
                }
            }
        }

        return ToolCallResponse(
            toolCalls: toolCalls,
            text: choice.message.content,
            usage: toTokenUsage(response.usage),
            stopReason: OpenAICompatibleStopReasonMapper.map(choice.finishReason),
            model: response.model
        )
    }

    /// OpenAI 互換レスポンスを ChatResponse に変換
    package static func toChatResponse<T: StructuredProtocol>(
        _ response: OpenAICompatibleResponseBody
    ) throws -> ChatResponse<T> {
        guard let choice = response.choices.first,
              let rawText = choice.message.content else {
            throw LLMError.emptyResponse
        }

        guard let jsonData = rawText.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let result: T
        do {
            result = try decoder.decode(T.self, from: jsonData)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return ChatResponse(
            result: result,
            assistantMessage: .assistant(rawText),
            usage: toTokenUsage(response.usage),
            stopReason: OpenAICompatibleStopReasonMapper.map(choice.finishReason),
            model: response.model,
            rawText: rawText
        )
    }

    /// OpenAI 互換レスポンスを GenerationResult に変換
    package static func toGenerationResult<T: StructuredProtocol>(
        _ response: LLMResponse,
        model: String
    ) throws -> GenerationResult<T> {
        guard let text = response.content.first?.text else {
            throw LLMError.emptyResponse
        }

        guard let data = text.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let result = try decoder.decode(T.self, from: data)
            return GenerationResult(
                result: result,
                usage: response.usage,
                model: model,
                rawText: text,
                stopReason: response.stopReason
            )
        } catch {
            throw LLMError.decodingFailed(error)
        }
    }

    /// OpenAI 互換 Usage → TokenUsage 変換
    package static func toTokenUsage(_ usage: OpenAICompatibleUsage) -> TokenUsage {
        let cachedTokens = usage.promptTokensDetails?.cachedTokens
        return TokenUsage(
            inputTokens: usage.promptTokens,
            outputTokens: usage.completionTokens,
            reasoningTokens: usage.completionTokensDetails?.reasoningTokens,
            cacheReadTokens: cachedTokens,
            cacheCreationTokens: nil,
            cacheTier: (cachedTokens ?? 0) > 0 ? .short : nil
        )
    }
}
