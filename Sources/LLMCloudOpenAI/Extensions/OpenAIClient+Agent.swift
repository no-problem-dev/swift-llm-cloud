import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool
import LLMAgentStep

// MARK: - OpenAIClient + AgentCapableClient routing

extension OpenAIClient {
    /// エージェントステップを実行する。
    ///
    /// **reasoning モデル(GPT-5 系)に function tools を渡すときは `/v1/responses`**。
    /// Chat Completions に送ると拒否される:
    ///
    /// > Function tools with reasoning_effort are not supported for gpt-5.6-luna
    /// > in /v1/chat/completions. To use function tools, use /v1/responses
    ///
    /// **`reasoning_effort` を送っていなくても拒否される。** これらのモデルは
    /// 既定で reasoning するため、指定の有無は関係ない。以前は
    /// 「effort が指定されているとき」だけ振り分けており、指定なしの呼び出し
    /// (A2UI の副エージェントなど)が Chat Completions に落ちて失敗していた。
    ///
    /// なので振り分けは**モデルで決める**:
    /// - reasoning モデル + tools あり → `/v1/responses`（OpenAIResponsesEngine）
    /// - それ以外 → Chat Completions（OpenAICompatibleEngine 経由のデフォルト実装）
    public func executeAgentStep(
        messages: [LLMMessage],
        model: GPTModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        _ = thinkingMode // OpenAI 系は Extended Thinking ではなく reasoning_effort で思考量を制御する

        // モデルが受け付ける段に寄せる（API 拒否回避）。対応する段はモデルの
        // 世代ごとに違う — GPT-5.6 は max まで、o-series は low/medium/high だけ、
        // minimal は 5.1 以降で none に置き換わった
        let effectiveEffort = reasoningEffort.flatMap(model.clamped)

        // **effort の有無ではなくモデルで決める。** reasoning モデルは既定で
        // 思考するので、effort を送っていなくても Chat Completions は
        // function tools を拒否する
        if model.supportsReasoningEffort, !tools.isEmpty {
            return try await responsesEngine.executeAgentStep(
                messages: messages,
                modelId: model.id,
                systemPrompt: systemPrompt,
                tools: tools,
                toolChoice: toolChoice,
                responseSchema: responseSchema,
                reasoningEffort: effectiveEffort,
                maxTokens: maxTokens
            )
        }

        return try await engine.executeAgentStep(
            messages: messages,
            modelId: model.id,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            reasoningEffort: effectiveEffort,
            maxTokens: maxTokens
        )
    }

    /// エージェントステップをストリーミング実行する。
    ///
    /// ストリーミングは常に `/v1/responses` 経由（`OpenAIResponsesEngine`）。
    /// `executeAgentStep` の reasoning_effort 依存の経路分岐をストリーミングに
    /// 持ち込まない — 「特定の設定のときだけストリーミングされない」という
    /// 分かりにくい条件を作らないため。thinking の有無ともストリーミング可否は独立。
    public func streamAgentStep(
        messages: [LLMMessage],
        model: GPTModel,
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
        _ = cachePolicy // OpenAI のプロンプトキャッシュは自動（明示パラメータなし）

        let effectiveEffort = reasoningEffort.flatMap(model.clamped)

        return responsesEngine.streamAgentStep(
            messages: messages,
            modelId: model.id,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            reasoningEffort: effectiveEffort,
            maxTokens: maxTokens
        )
    }
}
