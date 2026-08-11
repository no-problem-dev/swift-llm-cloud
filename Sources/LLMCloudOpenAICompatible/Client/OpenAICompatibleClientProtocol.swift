import LLMClient
import LLMCloudClient
import LLMTool
import LLMAgentStep
import LLMChat
import Foundation

/// What a vendor client has to supply to get the whole OpenAI-compatible feature set for free.
///
/// A conforming type only provides an engine and a model type; the default implementations below
/// then satisfy `StructuredLLMClient`, `ChatCapableClient`, `ToolCallableClient`, and
/// `AgentCapableClient` by forwarding to it. That is why the DeepSeek, Groq, Mistral, OpenRouter,
/// and xAI clients are each barely more than a constructor.
package protocol OpenAICompatibleClientProtocol:
    StructuredLLMClient,
    ChatCapableClient,
    ToolCallableClient,
    AgentCapableClient
where Model: OpenAICompatibleModelProtocol {
    var engine: OpenAICompatibleEngine { get }
}

// MARK: - StructuredLLMClient Default Implementation

extension OpenAICompatibleClientProtocol {
    public var provider: any LLMProvider { engine.provider }

    public func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: Model,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await engine.generateWithUsage(
            input: input,
            modelId: model.id,
            toLLMModel: { model.toLLMModel() },
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await engine.generateWithUsage(
            messages: messages,
            modelId: model.id,
            toLLMModel: { model.toLLMModel() },
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

// MARK: - ChatCapableClient Default Implementation

extension OpenAICompatibleClientProtocol {
    public func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        try await engine.chat(
            messages: messages,
            modelId: model.id,
            systemPrompt: systemPrompt,
            responseSchema: T.jsonSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

// MARK: - ToolCallableClient Default Implementation

extension OpenAICompatibleClientProtocol {
    /// Asks the model which tools to call, without running any of them.
    ///
    /// The cache policy is not forwarded: this wire format exposes no prompt-cache controls, so
    /// whether a prefix is cached is entirely the vendor's decision.
    public func planToolCalls(
        messages: [LLMMessage],
        model: Model,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        try await engine.planToolCalls(
            messages: messages,
            modelId: model.id,
            tools: tools,
            toolChoice: toolChoice,
            systemPrompt: systemPrompt?.render(),
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

// MARK: - AgentCapableClient Default Implementation

extension OpenAICompatibleClientProtocol {
    /// Runs one agent turn against the vendor.
    ///
    /// Two arguments stop here rather than reaching the vendor: the thinking mode, which has no
    /// counterpart in this wire format — reasoning effort is the equivalent knob — and the cache
    /// policy, since there are no prompt-cache controls to apply it to.
    public func executeAgentStep(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        _ = thinkingMode // No thinking mode on this wire format; reasoning effort is the knob here.
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

    /// Runs one agent turn against the vendor, yielding text as it is generated.
    ///
    /// This overrides the protocol's default, which would run the whole call to completion and hand
    /// the caller a single `.completed` event — a stream in type only. Every vendor on this wire
    /// format documents `stream: true` on the chat-completions endpoint, so there is a real stream
    /// to consume and the engine consumes it.
    ///
    /// The same two arguments stop here as on the buffered path: the thinking mode, which this wire
    /// format has no counterpart for, and the cache policy, since there are no prompt-cache controls
    /// to apply it to.
    public func streamAgentStep(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        _ = thinkingMode // No thinking mode on this wire format; reasoning effort is the knob here.
        return engine.streamAgentStep(
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

