import LLMCloudClient
import LLMClient
import APIClient
import JSONParsing
import Foundation
import HTTPTransport

extension AnthropicClient {
    /// Streams the assistant's visible text as it is generated.
    ///
    /// Only `text_delta` payloads are yielded: thinking and tool-argument deltas are dropped, and
    /// no tools are sent, so this is the plain-prose path. The stream finishes when Anthropic
    /// closes it, and cancelling the consuming task cancels the request. Token usage is not
    /// surfaced here even though the stream carries it. Without an explicit limit, 4096 is sent
    /// as `max_tokens`, which Anthropic requires.
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

    /// Streams the assistant's visible text for a multi-turn conversation.
    ///
    /// Same filtering as the single-input form: `text_delta` only, no tools, and no usage
    /// reporting. A failure before the stream opens is thrown, but Anthropic's in-band `error`
    /// event is not recognized here — a stream that fails midway simply ends early, so a
    /// truncated answer is indistinguishable from a complete one.
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
                    for try await event in baseProvider.streamMessageEvents(body, beta: AnthropicProvider.betaValues(for: messages)) {
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

    /// Pulls assistant text out of one event, or `nil` if the event carries none.
    ///
    /// The event kind is taken from the `type` field inside the payload rather than the SSE
    /// `event:` line. Only `content_block_delta` payloads with a `text` field qualify, so
    /// thinking deltas and `input_json_delta` tool-argument fragments are skipped.
    private static func extractTextDelta(from event: SSEEvent) -> String? {
        guard let e = AnthropicSSE.decode(AnthropicSSE.TextDelta.self, from: event.data),
              e.type.flatMap(AnthropicSSE.EventName.init(rawValue:)) == .contentBlockDelta else {
            return nil
        }
        return e.delta?.text
    }
}
