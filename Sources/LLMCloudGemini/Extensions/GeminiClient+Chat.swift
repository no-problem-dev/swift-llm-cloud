import LLMCloudClient
import LLMClient
import LLMChat
import Foundation

extension GeminiClient: ChatCapableClient {
    public func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        let contents = messages.flatMap { GeminiContentConverter.convert($0) }

        var systemInstruction: GeminiContent?
        if let systemPrompt, !systemPrompt.isEmpty {
            systemInstruction = GeminiContent(role: "user", parts: [GeminiPart(text: systemPrompt)])
        }

        var generationConfig = GeminiGenerationConfig(
            maxOutputTokens: maxTokens ?? Self.chatDefaultMaxTokens,
            temperature: temperature
        )
        generationConfig.responseMimeType = "application/json"
        generationConfig.responseSchema = GeminiSchemaAdapter().adapt(T.jsonSchema)

        let body = GeminiRequestBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            tools: nil,
            toolConfig: nil
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
