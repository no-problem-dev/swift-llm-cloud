import APIClient
import Foundation
import JSONParsing
import LLMAgentStep
import LLMClient
import LLMCloudClient
import LLMTool

// MARK: - Streaming Agent Step

extension GeminiClient {
    /// エージェントステップをストリーミング実行
    ///
    /// `streamGenerateContent`（SSE）でテキストデルタをリアルタイムに返す。
    /// thinking の有無に関わらず常にストリーミングする（thinking 制御は
    /// `reasoningEffort` 由来の `thinkingConfig` で行い、ストリーミング可否とは独立）。
    ///
    /// ストリーミング経路はリトライしない（途中失敗の再試行はデルタ重複になるため）。
    /// キャッシュ失効（`GeminiCachedContentError.notFound`）のみ、デルタ送出前に限り
    /// キャッシュ再作成 + 1 回リトライで回復する。
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

/// SSE チャンク（各チャンク = `GeminiResponseBody` 全体）からストリーミングデルタと
/// 完全レスポンスを構築するアキュムレータ
///
/// Anthropic のブロック指向 SSE と違い、Gemini のチャンクは自己完結している:
/// - テキストは `parts[].text` の増分（連結して全文になる）
/// - `functionCall` は 1 チャンクに完全体（`args` はパース済み構造）で届く
/// - `usageMetadata` は毎チャンク累積値なので加算せず上書きする
/// - `finishReason` は最終チャンクにのみ入る
/// - 明示的な完了イベントは無く、ストリームの EOF が正常終了
struct GeminiStreamAccumulator {
    enum Action {
        case yieldDelta(StreamDelta)
        case error(LLMError)
    }

    private var textContent = ""
    private var toolUseBlocks: [(id: String, name: String, input: Data)] = []
    private var latestUsage: GeminiUsageMetadata?
    private var finishReason: String?

    /// まだ何も蓄積していないか（キャッシュ失効リトライの可否判定に使う）
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
                // encodeToolCallId は UUID を含むため、functionCall 検出時に一度だけ呼んで保持する
                toolUseBlocks.append((
                    id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                    name: functionCall.name,
                    input: input
                ))
            }
        }
        return actions
    }

    /// ストリーム終端（EOF）で完全レスポンスを構築する
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
