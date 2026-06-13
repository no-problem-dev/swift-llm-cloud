import LLMCloudClient
import LLMClient
import LLMTool
import LLMAgentStep
import APIClient
import Foundation

// MARK: - AnthropicClient + AgentCapableClient

extension AnthropicClient: AgentCapableClient {
    /// エージェントステップを実行
    ///
    /// Anthropic Claude API を使用してエージェントステップを実行します。
    /// ツールコールと構造化出力の両方をサポートします。
    /// リトライ設定に基づいて、レート制限やサーバーエラー時に自動リトライを行います。
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
            toolChoice: anthropicToolChoice
        )

        let beta = responseSchema != nil ? Self.structuredOutputsBeta : nil
        let response = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.baseProvider.sendBody(body, beta: beta).0
        }
        return Self.agentResponseToLLM(response)
    }

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

    /// 構造化出力のベータヘッダー
    private static let structuredOutputsBeta = "structured-outputs-2025-11-13"

    /// デフォルトの最大トークン数（non-thinking 用）
    private static let defaultMaxTokens = 4096

    /// Extended Thinking 有効時のデフォルト最大トークン数
    private static let defaultMaxTokensWithThinking = 16384

    /// Extended Thinking 有効時のデフォルト思考バジェットトークン数
    ///
    /// `defaultMaxTokensWithThinking` (16384) のうち 10240 を思考に割り当て、
    /// 残り 6144 を出力用に確保します。
    private static let defaultThinkingBudgetTokens = 10240

    // MARK: - Private Helpers

    // MARK: - Streaming Agent Step

    /// エージェントステップをストリーミング実行
    ///
    /// thinking が有効な場合、SSE ストリーミングで thinking_delta/text_delta をリアルタイムに返します。
    /// thinking が無効な場合は既存の `executeAgentStep()` にフォールバックします。
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
        _ = reasoningEffort // Anthropic 側では Extended Thinking が思考量制御の主役

        // 非対応モデル（Haiku 等）は自動で thinking 無効にフォールバック
        let effectiveThinkingMode: ThinkingMode
        if thinkingMode == .adaptive && !model.supportsExtendedThinking {
            effectiveThinkingMode = .disabled
        } else {
            effectiveThinkingMode = thinkingMode
        }

        // thinking 無効時はデフォルト実装（非ストリーミング）にフォールバック
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
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// ストリーミングリクエストを実行
    private func executeStreamingAgentStep(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?,
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
            thinking: AnthropicThinkingConfig(type: "enabled", budgetTokens: effectiveBudget)
        )
        let beta = responseSchema != nil ? Self.structuredOutputsBeta : nil

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

/// SSE イベントからストリーミングデルタと完全レスポンスを生成するアキュムレータ
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

    /// ストリーム終了後にまだレスポンスが返されていない場合に最終レスポンスを構築
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

    private mutating func processContentBlockStop() -> [Action] {
        // thinking ブロック完了
        if !currentThinkingText.isEmpty {
            thinkingTexts.append((text: currentThinkingText, signature: currentThinkingSignature))
            currentThinkingText = ""
            currentThinkingSignature = nil
        }

        // tool_use ブロック完了
        if let id = currentToolId, let name = currentToolName {
            toolUseBlocks.append((id: id, name: name, inputJSON: currentToolInput))
            currentToolId = nil
            currentToolName = nil
            currentToolInput = ""
        }

        return []
    }

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

    private mutating func processError(_ data: String) -> [Action] {
        let message = AnthropicSSE.decode(AnthropicSSE.ErrorEvent.self, from: data)?.error.message
        return [.error(.serverError(0, message ?? "Unknown streaming error"))]
    }

    // MARK: - Response Building

    private func buildResponse() -> LLMResponse? {
        var contentBlocks: [LLMResponse.ContentBlock] = []

        // thinking ブロック
        for thinking in thinkingTexts {
            contentBlocks.append(.thinking(text: thinking.text, signature: thinking.signature))
        }

        // テキストブロック
        if !textContent.isEmpty {
            contentBlocks.append(.text(textContent))
        }

        // tool_use ブロック
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
