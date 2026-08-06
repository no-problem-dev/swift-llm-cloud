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
    /// OpenAI の reasoning モデル (GPT-5 系) では、function tools と `reasoning_effort` を
    /// 同時に Chat Completions に送ると `Invalid request: Function tools with reasoning_effort
    /// are not supported ... Please use /v1/responses instead` で拒否される。
    ///
    /// そのため、本実装では:
    /// - `reasoningEffort` が指定され、かつ `tools` が空でない場合は `/v1/responses` 経由（OpenAIResponsesEngine）
    /// - それ以外は既存の Chat Completions 経路（OpenAICompatibleEngine 経由のデフォルト実装）
    ///
    /// にディスパッチする。Chat Completions 経路に流れた場合の挙動は従来と同一。
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

        if effectiveEffort != nil, !tools.isEmpty {
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
