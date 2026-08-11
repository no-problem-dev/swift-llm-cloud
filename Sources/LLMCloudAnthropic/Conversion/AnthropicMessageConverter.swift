import Foundation
import LLMClient

/// Lowers provider-neutral messages into Anthropic's message shape.
///
/// Shared by the send, chat, tool-calling, and token counting paths, which is what keeps a
/// count_tokens estimate equal to the request it estimates.
enum AnthropicMessageConverter {
    /// Converts one message, mapping every role other than user to assistant.
    ///
    /// Thinking blocks are dropped unless `includeThinking` is set. Replaying them matters for
    /// multi-turn reasoning — Anthropic wants the block and its signature back — but sending
    /// them where they are not wanted is rejected, so the caller decides.
    ///
    /// Audio and video have no representation in the Messages API and throw
    /// `LLMError.mediaNotSupported`; images and documents pass through as base64, URL, or
    /// `file_id` references, the last of which requires the Files API beta header.
    static func convert(_ message: LLMMessage, includeThinking: Bool = false) throws -> AnthropicMessage {
        let role = message.role == .user ? "user" : "assistant"
        var blocks: [AnthropicMessageContent] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                blocks.append(.text(text))
            case .toolUse(let id, let name, let input):
                blocks.append(.toolUse(id: id, name: name, input: input))
            case .toolResult(let toolCallId, _, let resultContent):
                blocks.append(.toolResult(
                    toolUseId: toolCallId,
                    content: resultContent.contentValue,
                    isError: resultContent.isError
                ))
            case .image(let imageContent):
                blocks.append(.image(imageContent))
            case .document(let documentContent):
                blocks.append(.document(documentContent))
            case .audio:
                throw LLMError.mediaNotSupported(mediaType: "audio", provider: "Anthropic")
            case .video:
                throw LLMError.mediaNotSupported(mediaType: "video", provider: "Anthropic")
            case .thinking(let text, let signature):
                if includeThinking {
                    blocks.append(.thinking(text: text, signature: signature))
                }
            }
        }

        return AnthropicMessage(role: role, content: blocks)
    }
}
