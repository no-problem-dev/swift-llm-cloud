import LLMCloudClient
import LLMClient
import LLMTool
import LLMAgentStep
import Foundation

/// エージェントステップ用に構築済みのリクエスト（ボディ + キャッシュ回復に使う安定プレフィックス）
struct GeminiAgentStepRequest: Sendable {
    let body: GeminiRequestBody
    let prefix: GeminiStablePrefix
}

extension GeminiClient: AgentCapableClient {
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

    /// エージェントステップのリクエストを構築する（非ストリーミング/ストリーミング共用）
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

    /// `ReasoningEffort` を Gemini の `thinkingConfig` にマップする。
    /// 3 系: thinkingLevel 文字列。2.5 系: thinkingBudget 整数。
    private static func thinkingConfig(for effort: ReasoningEffort, model: GeminiModel) -> GeminiThinkingConfig {
        switch model.thinkingControlStyle {
        case .level:
            let level: String
            switch effort {
            case .minimal: level = model.supportsMinimalThinkingLevel ? "minimal" : "low"
            case .low: level = "low"
            case .medium: level = "medium"
            case .high: level = "high"
            }
            return GeminiThinkingConfig(thinkingLevel: level, thinkingBudget: nil)
        case .budget:
            let budget: Int
            switch effort {
            case .minimal: budget = model.canDisableThinking ? 0 : 128
            case .low: budget = 1024
            case .medium: budget = 8192
            case .high: budget = 24576
            }
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: budget)
        case .unsupported:
            return GeminiThinkingConfig(thinkingLevel: nil, thinkingBudget: nil)
        }
    }

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
