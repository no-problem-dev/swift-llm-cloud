import LLMClient
import LLMCloudClient
import LLMTool
import LLMChat
import Foundation

/// OpenAI 互換クライアントプロトコル
///
/// このプロトコルに準拠することで、`StructuredLLMClient`、`ChatCapableClient`、
/// `ToolCallableClient`、`AgentCapableClient` の全機能をデフォルト実装で取得できる。
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
    public func planToolCalls(
        messages: [LLMMessage],
        model: Model,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?
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
    public func executeAgentStep(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        _ = thinkingMode // OpenAI 互換は thinking モード未対応
        return try await engine.executeAgentStep(
            messages: messages,
            modelId: model.id,
            systemPrompt: systemPrompt,
            tools: tools,
            toolChoice: toolChoice,
            responseSchema: responseSchema,
            maxTokens: maxTokens
        )
    }
}

