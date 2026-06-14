import Foundation
import LLMClient

enum AnthropicMessageConverter {
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
