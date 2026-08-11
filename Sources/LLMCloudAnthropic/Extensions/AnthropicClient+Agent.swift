import LLMCloudClient
import LLMClient
import LLMTool
import LLMAgentStep
import APIClient
import Foundation

// MARK: - AnthropicClient + AgentCapableClient

extension AnthropicClient: AgentCapableClient {
    /// Runs one agent turn and returns the complete reply.
    ///
    /// Tool definitions and a response schema can be combined in the same request: tools become
    /// Anthropic tool definitions, and the schema becomes an `output_config.format` for
    /// constrained decoding. Thinking blocks already in the history are replayed with their
    /// signatures, which Anthropic requires when a conversation continues after reasoning.
    ///
    /// This path does not request extended thinking — both `thinkingMode` and `reasoningEffort`
    /// are ignored here, and no thinking budget is sent. Use the streaming form for reasoning.
    ///
    /// Rate-limited and server-error responses are retried according to the client's retry
    /// configuration, waiting as long as the `anthropic-ratelimit-*` headers ask for.
    public func executeAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        _ = reasoningEffort
        _ = thinkingMode

        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0, includeThinking: true) }
        let anthropicTools = tools.isEmpty ? nil : tools.toAnthropicToolDefs()
        let anthropicToolChoice: AnthropicToolChoiceValue? = tools.isEmpty
            ? nil
            : (toolChoice.map { AnthropicToolChoiceValue($0) } ?? .auto)
        let outputConfig = responseSchema.map {
            AnthropicOutputConfig(format: AnthropicOutputFormat(type: "json_schema", schema: $0))
        }

        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: maxTokens ?? Self.defaultMaxTokens,
            temperature: nil,
            outputConfig: outputConfig,
            tools: anthropicTools,
            toolChoice: anthropicToolChoice,
            cachePolicy: cachePolicy
        )

        // Structured output needs no beta flag. Only file_id references and the one-hour cache
        // TTL do, and only when the request actually uses them.
        let beta = AnthropicProvider.betaValues(for: messages) + body.cacheBetaValues
        let response = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.baseProvider.sendBody(body, beta: beta).0
        }
        return Self.agentResponseToLLM(response)
    }

    /// Converts a reply into the neutral response shape, keeping thinking blocks.
    ///
    /// Unlike the plain send path, reasoning survives here with its signature so the caller can
    /// replay it on the next turn. A tool use whose arguments fail to re-encode is dropped
    /// rather than failing the turn, which can leave an agent loop with fewer calls than
    /// Anthropic actually requested.
    private static func agentResponseToLLM(_ response: AnthropicResponseBody) -> LLMResponse {
        let contentBlocks: [LLMResponse.ContentBlock] = response.content.compactMap { block in
            switch AnthropicBlockType(rawValue: block.type) {
            case .text:
                return block.text.map { .text($0) }
            case .toolUse:
                guard let id = block.id, let name = block.name, let input = block.input,
                      let inputData = try? JSONEncoder().encode(input) else { return nil }
                return .toolUse(id: id, name: name, input: inputData)
            case .thinking:
                return block.text.map { .thinking(text: $0, signature: block.signature) }
            case nil:
                return nil
            }
        }
        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }
        )
    }

    // MARK: - Private Constants

    /// Output limit sent for a turn without extended thinking, since Anthropic requires one.
    private static let defaultMaxTokens = 4096

    /// Larger output limit used when extended thinking is on, since reasoning is billed as output.
    private static let defaultMaxTokensWithThinking = 16384

    /// Share of the output budget reserved for reasoning when extended thinking is on.
    ///
    /// Anthropic counts the thinking budget inside `max_tokens`, so with the default 16384 this
    /// leaves 6144 for the visible answer. A caller-supplied `max_tokens` clamps the budget to
    /// one token below it, because Anthropic rejects a budget equal to the limit.
    private static let defaultThinkingBudgetTokens = 10240

    // MARK: - Private Helpers

    // MARK: - Streaming Agent Step

    /// Runs one agent turn, streaming reasoning and text as they are produced.
    ///
    /// With extended thinking on, `thinking_delta` and `text_delta` events are forwarded as they
    /// arrive and a final assembled response is yielded at the end. Tool arguments are not
    /// streamed: their `input_json_delta` fragments are only valid JSON once concatenated, so
    /// tool calls appear whole in the final response.
    ///
    /// Extended thinking is dropped for models that do not support it — Haiku, and the Opus 4.7
    /// and 4.8 generations — in which case this falls back to a single non-streaming request and
    /// emits one completed event. Note that a model with no thinking support therefore streams
    /// nothing at all, even though the call signature promises a stream.
    public func streamAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        _ = reasoningEffort // On Anthropic the thinking budget, not an effort knob, governs reasoning.

        // Models without extended thinking support silently drop to the non-thinking path.
        let effectiveThinkingMode: ThinkingMode
        if thinkingMode == .adaptive && !model.supportsExtendedThinking {
            effectiveThinkingMode = .disabled
        } else {
            effectiveThinkingMode = thinkingMode
        }

        // Without thinking there is nothing to stream incrementally: run one blocking request
        // and hand back its result as a single completed event.
        guard effectiveThinkingMode == .adaptive else {
            return makeCancellableStream { continuation in
                Task {
                    do {
                        let response = try await executeAgentStep(
                            messages: messages,
                            model: model,
                            systemPrompt: systemPrompt,
                            tools: tools,
                            toolChoice: toolChoice,
                            responseSchema: responseSchema,
                            thinkingMode: effectiveThinkingMode,
                            reasoningEffort: nil,
                            maxTokens: maxTokens,
                            cachePolicy: cachePolicy
                        )
                        continuation.yield(.completed(response))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

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

    /// Issues the streaming request and drives the accumulator that reassembles it.
    ///
    /// The final response is emitted from `message_stop`; if the stream ends without one, a
    /// response is still built from whatever accumulated, so a truncated stream yields partial
    /// content rather than nothing. Unlike the non-streaming path, this request is not retried.
    private func executeStreamingAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy,
        continuation: AsyncThrowingStream<StreamingAgentEvent, Error>.Continuation
    ) async throws {
        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0, includeThinking: true) }
        let anthropicTools = tools.isEmpty ? nil : tools.toAnthropicToolDefs()
        let anthropicToolChoice: AnthropicToolChoiceValue? = tools.isEmpty
            ? nil
            : (toolChoice.map { AnthropicToolChoiceValue($0) } ?? .auto)
        let outputConfig = responseSchema.map {
            AnthropicOutputConfig(format: AnthropicOutputFormat(type: "json_schema", schema: $0))
        }

        let effectiveMaxTokens = maxTokens ?? Self.defaultMaxTokensWithThinking
        let effectiveBudget = min(Self.defaultThinkingBudgetTokens, effectiveMaxTokens - 1)

        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: systemPrompt?.render(),
            maxTokens: effectiveMaxTokens,
            outputConfig: outputConfig,
            tools: anthropicTools,
            toolChoice: anthropicToolChoice,
            stream: true,
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: effectiveBudget),
            cachePolicy: cachePolicy
        )
        // Structured output needs no beta flag. Only file_id references and the one-hour cache
        // TTL do, and only when the request actually uses them.
        let beta = AnthropicProvider.betaValues(for: messages) + body.cacheBetaValues

        var accumulator = AnthropicStreamAccumulator()
        for try await event in baseProvider.streamMessageEvents(body, beta: beta) {
            for action in accumulator.processEvent(event) {
                switch action {
                case .yieldDelta(let delta):
                    continuation.yield(.delta(delta))
                case .yieldCompleted(let response):
                    continuation.yield(.completed(response))
                case .error(let error):
                    continuation.finish(throwing: error)
                    return
                }
            }
        }

        if let response = accumulator.buildFinalResponse() {
            continuation.yield(.completed(response))
        }
        continuation.finish()
    }
}

// MARK: - AnthropicStreamAccumulator

/// Reassembles a streamed Anthropic message from its server-sent events.
///
/// It holds the state the events themselves do not repeat: the id and name of the tool-use block
/// currently open, the thinking signature being built, and the usage counters, which arrive
/// split between `message_start` (input and cache) and `message_delta` (final output).
///
/// Text and thinking are emitted as deltas the moment they arrive. Tool arguments are not:
/// Anthropic sends them as `input_json_delta` fragments that are pieces of one JSON document, so
/// nothing is parseable until `content_block_stop` closes the block. The concatenated string is
/// handed on as-is without a parse check, which means a stream cut mid-block produces a tool
/// call carrying truncated JSON.
private struct AnthropicStreamAccumulator {
    enum Action {
        case yieldDelta(StreamDelta)
        case yieldCompleted(LLMResponse)
        case error(LLMError)
    }

    private var thinkingTexts: [(text: String, signature: String?)] = []
    private var currentThinkingText = ""
    private var currentThinkingSignature: String?
    private var textContent = ""
    private var toolUseBlocks: [(id: String, name: String, inputJSON: String)] = []
    private var currentToolId: String?
    private var currentToolName: String?
    private var currentToolInput = ""
    private var model = ""
    private var inputTokens = 0
    private var outputTokens = 0
    private var cacheCreationTokens: Int?
    private var cacheReadTokens: Int?
    private var stopReason: String?
    private var completed = false

    /// Folds one event into the accumulated state and returns whatever should be emitted now.
    ///
    /// Most events emit nothing. Events this client does not model are ignored, so an unknown
    /// event name is skipped rather than treated as a failure.
    mutating func processEvent(_ event: SSEEvent) -> [Action] {
        switch event.event.flatMap(AnthropicSSE.EventName.init) {
        case .messageStart:
            return processMessageStart(event.data)
        case .contentBlockStart:
            return processContentBlockStart(event.data)
        case .contentBlockDelta:
            return processContentBlockDelta(event.data)
        case .contentBlockStop:
            return processContentBlockStop()
        case .messageDelta:
            return processMessageDelta(event.data)
        case .messageStop:
            return processMessageStop()
        case .error:
            return processError(event.data)
        case nil:
            return []
        }
    }

    /// Builds a response for a stream that ended without a `message_stop` event.
    ///
    /// Returns `nil` when the stop event already produced one, so a normal stream does not emit
    /// its result twice. After an early end the usage is whatever had arrived, meaning the
    /// output token count is short of the real one.
    func buildFinalResponse() -> LLMResponse? {
        guard !completed else { return nil }
        return buildResponse()
    }

    // MARK: - Private Event Handlers

    private mutating func processMessageStart(_ data: String) -> [Action] {
        guard let event = AnthropicSSE.decode(AnthropicSSE.MessageStart.self, from: data) else { return [] }
        model = event.message.model ?? ""
        if let usage = event.message.usage {
            inputTokens = usage.inputTokens ?? 0
            outputTokens = usage.outputTokens ?? 0
            cacheCreationTokens = usage.cacheCreationInputTokens
            cacheReadTokens = usage.cacheReadInputTokens
        }
        return []
    }

    private mutating func processContentBlockStart(_ data: String) -> [Action] {
        guard let block = AnthropicSSE.decode(AnthropicSSE.ContentBlockStart.self, from: data)?.contentBlock else { return [] }

        switch AnthropicBlockType(rawValue: block.type) {
        case .thinking:
            currentThinkingText = ""
            currentThinkingSignature = nil
        case .text:
            break
        case .toolUse:
            currentToolId = block.id
            currentToolName = block.name
            currentToolInput = ""
        case nil:
            break
        }
        return []
    }

    /// Routes one delta by its own `type` field to the buffer it belongs to.
    ///
    /// Text and thinking are both buffered and emitted immediately. A signature delta only
    /// accumulates, since a partial signature is useless on its own, and `input_json_delta`
    /// fragments only accumulate because a fragment of a JSON document cannot be parsed.
    private mutating func processContentBlockDelta(_ data: String) -> [Action] {
        guard let delta = AnthropicSSE.decode(AnthropicSSE.ContentBlockDelta.self, from: data)?.delta else { return [] }

        switch delta.type.flatMap(AnthropicSSE.DeltaType.init) {
        case .thinkingDelta:
            if let thinking = delta.thinking {
                currentThinkingText += thinking
                return [.yieldDelta(.thinkingDelta(thinking))]
            }
        case .signatureDelta:
            if let signature = delta.signature {
                currentThinkingSignature = (currentThinkingSignature ?? "") + signature
            }
        case .textDelta:
            if let text = delta.text {
                textContent += text
                return [.yieldDelta(.textDelta(text))]
            }
        case .inputJsonDelta:
            if let partialJson = delta.partialJson {
                currentToolInput += partialJson
            }
        case nil:
            break
        }
        return []
    }

    /// Seals whichever block was open, moving its buffer into the finished list.
    ///
    /// The event does not say which block it closes, so both candidates are checked. A thinking
    /// block that produced only a signature and no prose is discarded.
    private mutating func processContentBlockStop() -> [Action] {
        // Thinking block finished.
        if !currentThinkingText.isEmpty {
            thinkingTexts.append((text: currentThinkingText, signature: currentThinkingSignature))
            currentThinkingText = ""
            currentThinkingSignature = nil
        }

        // Tool use finished: the fragments collected so far are the whole argument document.
        if let id = currentToolId, let name = currentToolName {
            toolUseBlocks.append((id: id, name: name, inputJSON: currentToolInput))
            currentToolId = nil
            currentToolName = nil
            currentToolInput = ""
        }

        return []
    }

    /// Takes the stop reason and the final output token count off the closing delta.
    ///
    /// This event does not repeat the input or cache counters from `message_start`, and a
    /// missing output count leaves the previous value in place rather than resetting it to zero.
    private mutating func processMessageDelta(_ data: String) -> [Action] {
        guard let event = AnthropicSSE.decode(AnthropicSSE.MessageDelta.self, from: data) else { return [] }
        stopReason = event.delta?.stopReason
        outputTokens = event.usage?.outputTokens ?? outputTokens
        return []
    }

    private mutating func processMessageStop() -> [Action] {
        completed = true
        if let response = buildResponse() {
            return [.yieldCompleted(response)]
        }
        return []
    }

    /// Converts an in-band error event into a failure that ends the stream.
    ///
    /// Anthropic reports mid-stream failures inside a body that already returned HTTP 200, so
    /// there is no status code to carry; zero stands in for one.
    private mutating func processError(_ data: String) -> [Action] {
        let message = AnthropicSSE.decode(AnthropicSSE.ErrorEvent.self, from: data)?.error.message
        return [.error(.serverError(0, message ?? "Unknown streaming error"))]
    }

    // MARK: - Response Building

    /// Assembles the buffered blocks into a response, or `nil` if nothing was collected.
    ///
    /// Blocks are ordered thinking, then text, then tool uses, and all text deltas are merged
    /// into one block regardless of how many the stream actually contained. Tool arguments are
    /// passed through as the raw accumulated bytes without validation. Usage is normalized so
    /// the cache counters are folded into the input total.
    private func buildResponse() -> LLMResponse? {
        var contentBlocks: [LLMResponse.ContentBlock] = []

        for thinking in thinkingTexts {
            contentBlocks.append(.thinking(text: thinking.text, signature: thinking.signature))
        }

        if !textContent.isEmpty {
            contentBlocks.append(.text(textContent))
        }

        for tool in toolUseBlocks {
            let inputData = tool.inputJSON.data(using: .utf8) ?? Data()
            contentBlocks.append(.toolUse(id: tool.id, name: tool.name, input: inputData))
        }

        guard !contentBlocks.isEmpty else { return nil }

        let parsedStopReason = stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        return LLMResponse(
            content: contentBlocks,
            model: model,
            usage: AnthropicUsageNormalizer.normalize(
                rawInputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            stopReason: parsedStopReason
        )
    }
}
