import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool
import LLMAgentStep

// MARK: - OpenAIClient + AgentCapableClient routing

extension OpenAIClient {
    /// Runs one agent step, choosing the endpoint that will accept the request.
    ///
    /// A reasoning model given function tools has to go to `/v1/responses`. Chat Completions
    /// refuses that combination outright:
    ///
    /// > Function tools with reasoning_effort are not supported for gpt-5.6-luna
    /// > in /v1/chat/completions. To use function tools, use /v1/responses
    ///
    /// The refusal does not depend on `reasoning_effort` being sent. These models reason by
    /// default, so a call that passes no effort at all is rejected just the same. Routing is
    /// therefore decided by the model, never by the presence of an effort:
    ///
    /// - Reasoning model with at least one tool: the Responses API.
    /// - Everything else: Chat Completions, through the shared OpenAI-compatible implementation.
    ///
    /// The requested effort is first clamped to a step the model accepts, since sending an
    /// unsupported one fails the whole request. `thinkingMode` is ignored: OpenAI has no
    /// extended-thinking switch and controls thinking through the effort instead.
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
        _ = thinkingMode // OpenAI has no extended-thinking switch; reasoning_effort sets the budget.

        // Move the effort to a step this model accepts, so the API does not reject the call.
        // The available steps differ by generation — GPT-5.6 goes up to max, the o-series has
        // only low/medium/high, and minimal was replaced by none from 5.1 onwards.
        let effectiveEffort = reasoningEffort.flatMap(model.clamped)

        // Decided by the model, not by whether an effort was passed: reasoning models think by
        // default, so Chat Completions rejects function tools even with no effort in the body.
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

    /// Runs one agent step and yields events as the response streams in.
    ///
    /// Streaming always goes to the Responses API, whatever the model and whether or not tools
    /// are attached. The model-dependent routing of the non-streaming path is deliberately not
    /// repeated here, so there is no configuration in which a caller silently stops receiving
    /// deltas. Whether the model reasons has no bearing on it either.
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
        _ = cachePolicy // OpenAI caches prompts automatically; there is no parameter to set.

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
