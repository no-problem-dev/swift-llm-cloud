import Foundation
import LLMClient
import LLMTool
import LLMChat

/// Turns a chat completion body into whichever shared response type the caller asked for.
package enum OpenAICompatibleResponseConverter {

    /// Converts a completion into the general response type.
    ///
    /// Only the first choice is read; anything the model produced under a higher `n` is discarded.
    /// A tool call survives only if its type is `function` and its argument string is valid UTF-8,
    /// so a malformed call disappears rather than surfacing as an error. An empty choice list is
    /// not an error either: it yields a response with no content but with usage still filled in,
    /// since the tokens were billed regardless.
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

    /// Converts a completion into the tool-call response type.
    ///
    /// Arguments stay as the raw bytes of the vendor's JSON string, unparsed, so the caller decides
    /// how to read them. Calls of any other type than `function`, and calls whose argument string
    /// is not valid UTF-8, are dropped. Text the model produced alongside its tool calls is kept.
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

    /// Decodes the completion text into the caller's type and packages it as a chat response.
    ///
    /// The raw text is kept alongside the decoded value, which is what makes a decoding failure
    /// diagnosable. Keys are matched from snake_case. A completion with no choices, or a first
    /// choice with no text, throws an empty-response error rather than returning an empty value.
    ///
    /// - Throws: `LLMError.emptyResponse` when there is no text, `invalidEncoding` when it is not
    ///   valid UTF-8, and `decodingFailed` when the text does not match the expected shape — which
    ///   is what a model ignoring the schema looks like from here.
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

    /// Decodes an already-converted response into the caller's type.
    ///
    /// Unlike the chat path this starts from the shared response type, so it reads only the first
    /// content block and ignores any tool calls that came with it.
    ///
    /// - Throws: `LLMError.emptyResponse` when the first block holds no text, `invalidEncoding`
    ///   when that text is not valid UTF-8, and `decodingFailed` when it does not match the
    ///   expected shape.
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

    /// Normalizes vendor token counters into the shared accounting shape.
    ///
    /// These vendors fold cached prompt tokens into the prompt count and report the cached figure
    /// only as a breakdown, so the input count is passed through untouched and the cached figure is
    /// recorded beside it — adding the two would double-count. Nothing is reported for cache
    /// writes, because caching here is implicit and never billed as a separate write.
    ///
    /// The cache tier is inferred, not reported: any cache hit at all is recorded as the short
    /// tier, since the wire format has no field distinguishing tiers.
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
