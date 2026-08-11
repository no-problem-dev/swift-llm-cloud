import LLMCloudClient
import LLMClient
import LLMTool
import LLMAgentStep
import Foundation

/// A built agent-step request, kept together with the prefix that produced it.
///
/// The prefix is retained because recovering from a lost cache means resolving it again, which
/// cannot be done from the encoded body alone.
struct GeminiAgentStepRequest: Sendable {
    let body: GeminiRequestBody
    let prefix: GeminiStablePrefix
}

extension GeminiClient: AgentCapableClient {
    /// Runs one agent step and waits for the complete response.
    ///
    /// Retries follow the client's retry configuration, and a cache the server no longer has is
    /// recovered inside each attempt by recreating it and sending once more. Tool calls come back
    /// as content blocks whose ids are minted locally, since Gemini supplies none; a thinking
    /// model's thought signature is carried inside that id so it can be echoed back next turn.
    ///
    /// Two parameters do not mean here what they mean on other providers: `thinkingMode` is
    /// ignored outright, because Gemini's thinking budget is driven by `reasoningEffort` alone,
    /// and `cachePolicy` selects whether the stable prefix is cached explicitly on the server
    /// rather than describing a cache the provider manages for you.
    public func executeAgentStep(
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
    ) async throws -> LLMResponse {
        _ = thinkingMode

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

        let response = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await self.sendBodyRecoveringCacheLoss(
                request.body,
                prefix: request.prefix,
                cachePolicy: cachePolicy,
                modelId: model.id
            ).0
        }
        return Self.agentResponseToLLM(response, model: model.id)
    }

    /// Builds the request for an agent step, shared by the streaming and non-streaming paths.
    ///
    /// Resolving the cache policy can create a cache resource, which is why this is async even
    /// though it sends no generation request itself. A thinking config is only attached for models
    /// that accept one, because sending it to a model that does not is an API error.
    func makeAgentStepRequest(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async -> GeminiAgentStepRequest {
        let contents = messages.flatMap { GeminiContentConverter.convert($0) }

        var systemInstruction: GeminiContent?
        if let prompt = systemPrompt {
            systemInstruction = GeminiContent(role: "user", parts: [GeminiPart(text: prompt.render())])
        }

        var generationConfig = GeminiGenerationConfig(
            maxOutputTokens: maxTokens ?? Self.agentDefaultMaxTokens,
            temperature: nil
        )
        if let schema = responseSchema {
            generationConfig.responseMimeType = "application/json"
            generationConfig.responseSchema = GeminiSchemaAdapter().adapt(schema)
        }
        if let effort = reasoningEffort, model.supportsThinkingConfig {
            generationConfig.thinkingConfig = Self.thinkingConfig(for: effort, model: model)
        }

        var geminiTools: [GeminiTool]?
        var toolConfig: GeminiToolConfig?
        if !tools.isEmpty {
            let declarations = tools.toGeminiFunctionDeclarations()
            geminiTools = [GeminiTool(functionDeclarations: declarations)]
            toolConfig = toolChoice.map { Self.agentToolConfig(for: $0) }
        }

        let prefix = GeminiStablePrefix(
            model: model.id,
            systemInstruction: systemInstruction,
            tools: geminiTools,
            toolConfig: toolConfig
        )
        let promptContext = await resolvePromptContext(prefix: prefix, cachePolicy: cachePolicy)

        let body = GeminiRequestBody(
            contents: contents,
            generationConfig: generationConfig,
            promptContext: promptContext
        )
        return GeminiAgentStepRequest(body: body, prefix: prefix)
    }

    private static let agentDefaultMaxTokens = 4096

    /// Maps a reasoning effort onto the thinking control the model actually accepts.
    ///
    /// Gemini 3 models take a `thinkingLevel` string, Gemini 2.5 models an integer
    /// `thinkingBudget`, and a model that supports neither gets an empty config.
    ///
    /// The effort scale is OpenAI's (none, minimal, low, medium, high, xhigh, max) but Gemini
    /// accepts only minimal, low, medium, and high, so the extremes are clamped: everything above
    /// high becomes high, and nothing switches thinking off on a Gemini 3 model. On the budget
    /// side, a model that cannot disable thinking gets the smallest non-zero budget instead of
    /// zero, since zero would be rejected.
    private static func thinkingConfig(for effort: ReasoningEffort, model: GeminiModel) -> GeminiThinkingConfig {
        switch model.thinkingControlStyle {
        case .level:
            let level: String
            switch effort {
            // There is no level below minimal, and not every model even accepts minimal.
            case .none, .minimal: level = model.supportsMinimalThinkingLevel ? "minimal" : "low"
            case .low: level = "low"
            case .medium: level = "medium"
            // Nothing above high exists, so xhigh and max land there too.
            case .high, .xhigh, .max: level = "high"
            }
            return GeminiThinkingConfig(thinkingLevel: level, thinkingBudget: nil)
        case .budget:
            let budget: Int
            switch effort {
            case .none, .minimal: budget = model.canDisableThinking ? 0 : 128
            case .low: budget = 1024
            case .medium: budget = 8192
            case .high, .xhigh, .max: budget = 24576
            }
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: budget)
        case .unsupported:
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: nil)
        }
    }

    /// Expresses a tool choice in Gemini's function-calling modes.
    ///
    /// Gemini has no way to demand one specific tool, so a named choice becomes the `ANY` mode
    /// narrowed to that single allowed function name.
    private static func agentToolConfig(for choice: ToolChoice) -> GeminiToolConfig {
        let config: GeminiFunctionCallingConfig
        switch choice {
        case .auto:
            config = GeminiFunctionCallingConfig(mode: "AUTO", allowedFunctionNames: nil)
        case .disabled:
            config = GeminiFunctionCallingConfig(mode: "NONE", allowedFunctionNames: nil)
        case .required:
            config = GeminiFunctionCallingConfig(mode: "ANY", allowedFunctionNames: nil)
        case .tool(let name):
            config = GeminiFunctionCallingConfig(mode: "ANY", allowedFunctionNames: [name])
        }
        return GeminiToolConfig(functionCallingConfig: config)
    }

    /// Converts a Gemini response into the shared shape, keeping usage even when it is empty.
    ///
    /// A response with no candidate or no content yields an empty content list rather than an
    /// error, so the caller still sees the token counts it was billed for. Each tool call gets a
    /// locally minted id that carries the part's thought signature, which the converter reads back
    /// when this turn is replayed to the model.
    private static func agentResponseToLLM(_ response: GeminiResponseBody, model: String) -> LLMResponse {
        let usage = response.usageMetadata.map { GeminiUsageNormalizer.normalize($0) } ?? .zero

        guard let candidate = response.candidates?.first, let content = candidate.content else {
            return LLMResponse(content: [], model: model, usage: usage, stopReason: nil)
        }

        var blocks: [LLMResponse.ContentBlock] = []
        for part in content.parts {
            if let text = part.text { blocks.append(.text(text)) }
            if let functionCall = part.functionCall {
                let argsData = (functionCall.args.flatMap { try? JSONEncoder().encode($0) }) ?? Data("{}".utf8)
                blocks.append(.toolUse(
                    id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                    name: functionCall.name,
                    input: argsData
                ))
            }
        }

        let stopReason = GeminiFinishReason.stopReason(candidate.finishReason)

        return LLMResponse(content: blocks, model: model, usage: usage, stopReason: stopReason)
    }
}
