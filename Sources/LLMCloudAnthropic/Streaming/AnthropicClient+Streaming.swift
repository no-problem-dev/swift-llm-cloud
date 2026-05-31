import LLMCloudClient
import LLMClient
import APIClient
import JSONParsing
import Foundation

extension AnthropicClient {
    public func streamText(
        input: LLMInput,
        model: ClaudeModel,
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
        model: ClaudeModel,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0) }
                    let body = AnthropicRequestBody(
                        model: model.id,
                        messages: anthropicMessages,
                        system: systemPrompt,
                        maxTokens: maxTokens ?? 4096,
                        temperature: temperature,
                        stream: true
                    )
                    for try await event in baseProvider.streamMessageEvents(body, beta: nil) {
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
        guard let e = AnthropicSSE.decode(AnthropicSSE.TextDelta.self, from: event.data),
              e.type.flatMap(AnthropicSSE.EventName.init(rawValue:)) == .contentBlockDelta else {
            return nil
        }
        return e.delta?.text
    }
}
