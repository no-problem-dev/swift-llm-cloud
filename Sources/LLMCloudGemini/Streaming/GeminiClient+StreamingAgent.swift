import APIClient
import Foundation
import JSONParsing
import LLMAgentStep
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - Streaming Agent Step

extension GeminiClient {
    /// Runs one agent step, emitting text deltas as they arrive and a full response at the end.
    ///
    /// Streaming is unconditional. Thinking is controlled through the reasoning effort, which
    /// becomes a thinking config on the request, and has no bearing on whether the step streams.
    ///
    /// This path does not retry: replaying a request that failed midway would repeat deltas the
    /// caller already saw. The one exception is a cache the server no longer has, and only while
    /// nothing has been emitted yet: the cache is recreated and the request sent once more, so
    /// the caller sees a single clean stream. A cache loss after the first delta propagates as an
    /// error instead.
    ///
    /// Tool calls do not stream. Gemini delivers each `functionCall` complete in one chunk, so
    /// they surface in the final response rather than as deltas.
    ///
    /// `thinkingMode` is ignored, since Gemini's thinking budget comes from `reasoningEffort`
    /// alone. `cachePolicy` selects whether the stable prefix is cached explicitly on the server,
    /// and therefore also decides whether the cache-loss recovery above is available at all.
    public func streamAgentStep(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        _ = thinkingMode

        return makeCancellableStream { continuation in
            Task {
                do {
                    try await self.executeStreamingAgentStep(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        toolChoice: toolChoice,
                        responseSchema: responseSchema,
                        reasoningEffort: reasoningEffort,
                        maxTokens: maxTokens,
                        cachePolicy: cachePolicy,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func executeStreamingAgentStep(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy,
        continuation: AsyncThrowingStream<StreamingAgentEvent, Error>.Continuation
    ) async throws {
        let request = await makeAgentStepRequest(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            reasoningEffort: reasoningEffort,
            maxTokens: maxTokens,
            cachePolicy: cachePolicy
        )

        var accumulator = GeminiStreamAccumulator()
        do {
            try await consumeStream(
                body: request.body,
                modelId: model.id,
                accumulator: &accumulator,
                continuation: continuation
            )
        } catch GeminiCachedContentError.notFound {
            guard accumulator.isEmpty,
                  case .cached = request.body.promptContext,
                  case .explicitPrefix(let ttl) = cachePolicy else {
                throw GeminiCachedContentError.notFound
            }
            await contextCache.invalidate(prefix: request.prefix)
            let recovered = await contextCache.resolve(prefix: request.prefix, ttl: ttl)
            let retryBody = GeminiRequestBody(
                contents: request.body.contents,
                generationConfig: request.body.generationConfig,
                promptContext: recovered
            )
            try await consumeStream(
                body: retryBody,
                modelId: model.id,
                accumulator: &accumulator,
                continuation: continuation
            )
        }

        continuation.yield(.completed(accumulator.buildResponse(model: model.id)))
        continuation.finish()
    }

    private func consumeStream(
        body: GeminiRequestBody,
        modelId: String,
        accumulator: inout GeminiStreamAccumulator,
        continuation: AsyncThrowingStream<StreamingAgentEvent, Error>.Continuation
    ) async throws {
        for try await event in baseProvider.streamContentEvents(body, modelId: modelId) {
            for action in accumulator.processChunk(event.data) {
                switch action {
                case .yieldDelta(let delta):
                    continuation.yield(.delta(delta))
                case .error(let error):
                    throw error
                }
            }
        }
    }
}

// MARK: - GeminiStreamAccumulator

/// Builds streaming deltas and the final response out of Gemini's SSE chunks.
///
/// Unlike Anthropic's block-oriented events, every Gemini chunk is a whole response body:
/// - Text arrives as an increment in `parts[].text` and is concatenated into the full answer.
/// - A `functionCall` arrives complete in one chunk, arguments already parsed, so tool calls are
///   never assembled from fragments and never carry a provider-supplied id.
/// - `usageMetadata` is a running total on every chunk, so it is overwritten rather than summed.
/// - `finishReason` appears only on the last chunk.
/// - There is no explicit completion event; the end of the stream is the successful end.
///
/// A chunk that fails to parse is skipped rather than treated as an error, since a malformed
/// chunk should not discard the text already accumulated.
struct GeminiStreamAccumulator {
    enum Action {
        case yieldDelta(StreamDelta)
        case error(LLMError)
    }

    private var textContent = ""
    private var toolUseBlocks: [(id: String, name: String, input: Data)] = []
    private var latestUsage: GeminiUsageMetadata?
    private var finishReason: String?

    /// Whether nothing has been observed yet, including usage and finish reason.
    ///
    /// The cache-loss retry is only safe while this holds: past that point the caller has already
    /// been handed deltas, and resending would duplicate them.
    var isEmpty: Bool {
        textContent.isEmpty && toolUseBlocks.isEmpty && latestUsage == nil && finishReason == nil
    }

    mutating func processChunk(_ data: String) -> [Action] {
        guard let chunk = try? JSONParser().parse(data).decode(GeminiResponseBody.self) else {
            return []
        }

        if let usage = chunk.usageMetadata {
            latestUsage = usage
        }

        if let blockReason = chunk.promptFeedback?.blockReason {
            return [.error(.contentBlocked(reason: blockReason))]
        }

        guard let candidate = chunk.candidates?.first else { return [] }
        if let reason = candidate.finishReason {
            finishReason = reason
        }

        var actions: [Action] = []
        for part in candidate.content?.parts ?? [] {
            if let text = part.text {
                textContent += text
                actions.append(.yieldDelta(.textDelta(text)))
            }
            if let functionCall = part.functionCall {
                let input = (functionCall.args.flatMap { try? JSONEncoder().encode($0) }) ?? Data("{}".utf8)
                // The id is minted here and stored, because it embeds a fresh UUID: calling the
                // encoder again later would produce a different id for the same call.
                toolUseBlocks.append((
                    id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                    name: functionCall.name,
                    input: input
                ))
            }
        }
        return actions
    }

    /// Assembles the complete response once the stream ends.
    ///
    /// Text comes first as a single joined block, then the tool calls in arrival order. Usage is
    /// taken from the last chunk that carried it and normalized; a stream that reported none
    /// yields zeros rather than an estimate.
    func buildResponse(model: String) -> LLMResponse {
        var blocks: [LLMResponse.ContentBlock] = []
        if !textContent.isEmpty {
            blocks.append(.text(textContent))
        }
        for tool in toolUseBlocks {
            blocks.append(.toolUse(id: tool.id, name: tool.name, input: tool.input))
        }
        return LLMResponse(
            content: blocks,
            model: model,
            usage: latestUsage.map { GeminiUsageNormalizer.normalize($0) } ?? .zero,
            stopReason: GeminiFinishReason.stopReason(finishReason)
        )
    }
}
