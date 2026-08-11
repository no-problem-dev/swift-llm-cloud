import LLMCloudClient
import LLMClient
import LLMChat
import Foundation

extension GeminiClient: ChatCapableClient {
    /// Continues a conversation and decodes the reply into a structured type.
    ///
    /// The response schema is adapted to Gemini's OpenAPI subset and sent with a JSON mime type,
    /// so the reply is parsed directly rather than being stripped of a markdown fence first. This
    /// path declares no tools, uses no prompt cache, and bypasses the retry layer.
    ///
    /// - Parameters:
    ///   - messages: The conversation so far, oldest first.
    ///   - model: Gemini model to answer the turn.
    ///   - options: System prompt, temperature, and output ceiling. An unset ceiling falls back to
    ///     4096 tokens.
    public func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: GeminiModel,
        options: ChatOptions
    ) async throws -> ChatResponse<T> {
        let contents = messages.flatMap { GeminiContentConverter.convert($0) }

        var systemInstruction: GeminiContent?
        if let systemPrompt = options.systemPrompt, !systemPrompt.isEmpty {
            systemInstruction = GeminiContent(role: "user", parts: [GeminiPart(text: systemPrompt)])
        }

        var generationConfig = GeminiGenerationConfig(
            maxOutputTokens: options.maxTokens ?? Self.chatDefaultMaxTokens,
            temperature: options.temperature
        )
        generationConfig.responseMimeType = "application/json"
        generationConfig.responseSchema = GeminiSchemaAdapter().adapt(T.jsonSchema)

        let body = GeminiRequestBody(
            contents: contents,
            generationConfig: generationConfig,
            promptContext: .inline(systemInstruction: systemInstruction, tools: nil, toolConfig: nil)
        )

        let (response, _, _) = try await baseProvider.sendBody(body, modelId: model.id)

        guard let candidate = response.candidates?.first,
              let rawText = candidate.content?.parts.first(where: { $0.text != nil })?.text else {
            throw LLMError.emptyResponse
        }
        guard let jsonData = rawText.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let resultDecoder = JSONDecoder()
        resultDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let result: T
        do {
            result = try resultDecoder.decode(T.self, from: jsonData)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        let stopReason = GeminiFinishReason.stopReason(candidate.finishReason)

        return ChatResponse(
            result: result,
            assistantMessage: .assistant(rawText),
            usage: response.usageMetadata.map { GeminiUsageNormalizer.normalize($0) } ?? .zero,
            stopReason: stopReason,
            model: model.id,
            rawText: rawText
        )
    }

    private static let chatDefaultMaxTokens = 4096
}
