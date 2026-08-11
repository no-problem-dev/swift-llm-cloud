import LLMCloudClient
import LLMClient
import LLMTool
import Foundation

extension GeminiClient: ToolCallableClient {
    /// Asks the model which tools to call, without running them.
    ///
    /// Gemini attaches no ids to its function calls, so each returned call gets one minted here,
    /// with the part's thought signature folded into it for the next turn. Tool results are later
    /// matched back by function name. A cache the server no longer has is recovered once inside
    /// this call; unlike the agent path, there is no retry policy around it.
    public func planToolCalls(
        messages: [LLMMessage],
        model: GeminiModel,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        let contents = messages.flatMap { GeminiContentConverter.convert($0) }

        var systemInstruction: GeminiContent?
        if let prompt = systemPrompt {
            systemInstruction = GeminiContent(role: "user", parts: [GeminiPart(text: prompt.render())])
        }

        let generationConfig = GeminiGenerationConfig(
            maxOutputTokens: maxTokens ?? Self.toolDefaultMaxTokens,
            temperature: temperature
        )

        var geminiTools: [GeminiTool]?
        var toolConfig: GeminiToolConfig?
        if !tools.isEmpty {
            let declarations = tools.toGeminiFunctionDeclarations()
            geminiTools = [GeminiTool(functionDeclarations: declarations)]
            toolConfig = toolChoice.map { Self.toolConfig(for: $0) }
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

        let (response, _, _) = try await sendBodyRecoveringCacheLoss(
            body, prefix: prefix, cachePolicy: cachePolicy, modelId: model.id
        )
        return Self.parseToolCallResponse(response, model: model.id)
    }

    private static let toolDefaultMaxTokens = 4096

    private static func toolConfig(for choice: ToolChoice) -> GeminiToolConfig {
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

    private static func parseToolCallResponse(_ response: GeminiResponseBody, model: String) -> ToolCallResponse {
        let usage = response.usageMetadata.map { GeminiUsageNormalizer.normalize($0) } ?? .zero

        guard let candidate = response.candidates?.first, let content = candidate.content else {
            return ToolCallResponse(toolCalls: [], text: nil, usage: usage, stopReason: nil, model: model)
        }

        var toolCalls: [ToolCall] = []
        var textContent: String?
        for part in content.parts {
            if let text = part.text { textContent = text }
            if let functionCall = part.functionCall {
                let argsData = (functionCall.args.flatMap { try? JSONEncoder().encode($0) }) ?? Data("{}".utf8)
                toolCalls.append(ToolCall(
                    id: GeminiThoughtSignatureEncoding.encodeToolCallId(thoughtSignature: part.thoughtSignature),
                    name: functionCall.name,
                    arguments: argsData
                ))
            }
        }

        return ToolCallResponse(
            toolCalls: toolCalls,
            text: textContent,
            usage: usage,
            stopReason: Self.mapStopReason(candidate.finishReason),
            model: model
        )
    }

    private static func mapStopReason(_ reason: String?) -> LLMResponse.StopReason? {
        GeminiFinishReason.stopReason(reason)
    }
}
