import LLMCloudClient
import LLMClient
import APIClient
import Foundation

extension GeminiClient {
    public func streamText(
        input: LLMInput,
        model: GeminiModel,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        streamText(
            messages: [input.toLLMMessage()],
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func streamText(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let contents = messages.flatMap { GeminiContentConverter.convert($0) }

                    var systemInstruction: GeminiContent?
                    if let systemPrompt, !systemPrompt.isEmpty {
                        systemInstruction = GeminiContent(role: "user", parts: [GeminiPart(text: systemPrompt)])
                    }

                    let generationConfig = GeminiGenerationConfig(
                        maxOutputTokens: maxTokens ?? 4096,
                        temperature: temperature
                    )

                    let body = GeminiRequestBody(
                        contents: contents,
                        systemInstruction: systemInstruction,
                        generationConfig: generationConfig,
                        tools: nil,
                        toolConfig: nil
                    )

                    for try await event in baseProvider.streamContentEvents(body, modelId: model.id) {
                        if let text = Self.extractTextDelta(from: event) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func extractTextDelta(from event: SSEEvent) -> String? {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }
        let textPieces = parts.compactMap { $0["text"] as? String }
        return textPieces.isEmpty ? nil : textPieces.joined()
    }
}
