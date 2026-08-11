import LLMCloudClient
import LLMClient
import APIClient
import StructuredDataCore
import JSONParsing
import Foundation

extension GeminiClient {
    /// Streams plain text for a single prompt.
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

    /// Streams plain text for a conversation, yielding each chunk's text as it arrives.
    ///
    /// Text only: no tools are declared, no response schema is set, and no prompt cache is used,
    /// so every request carries its full prefix. Streaming is never retried, and cancelling the
    /// stream cancels the request. Usage counters are not surfaced on this path.
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
                        generationConfig: generationConfig,
                        promptContext: .inline(systemInstruction: systemInstruction, tools: nil, toolConfig: nil)
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

    /// Pulls the text out of one SSE event, or nil when the chunk carries none.
    ///
    /// A chunk that fails to parse is skipped rather than failing the stream, and a chunk holding
    /// only a function call or usage totals simply has no text to yield.
    private static func extractTextDelta(from event: SSEEvent) -> String? {
        guard let chunk = try? JSONParser().parse(event.data).decode(GeminiResponseBody.self),
              let parts = chunk.candidates?.first?.content?.parts else {
            return nil
        }
        let textPieces = parts.compactMap(\.text)
        return textPieces.isEmpty ? nil : textPieces.joined()
    }
}
