import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool

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
        maxTokens: Int?
    ) async throws -> LLMResponse {
        _ = thinkingMode // OpenAI 系は Extended Thinking ではなく reasoning_effort で思考量を制御する

        if reasoningEffort != nil, !tools.isEmpty {
            return try await responsesEngine.executeAgentStep(
                messages: messages,
                modelId: model.id,
                systemPrompt: systemPrompt,
                tools: tools,
                toolChoice: toolChoice,
                responseSchema: responseSchema,
                reasoningEffort: reasoningEffort,
                maxTokens: maxTokens
            )
        }

        // 既存の Chat Completions 経路にフォールバック。
        return try await engine.executeAgentStep(
            messages: messages,
            modelId: model.id,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            reasoningEffort: reasoningEffort,
            maxTokens: maxTokens
        )
    }
}
