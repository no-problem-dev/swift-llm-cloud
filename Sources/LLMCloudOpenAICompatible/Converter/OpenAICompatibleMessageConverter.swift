import Foundation
import LLMClient
import LLMCloudClient

/// Rewrites the shared message model into the shape Chat Completions expects.
package enum OpenAICompatibleMessageConverter {

    /// Converts one shared message into the one or more wire messages it needs.
    ///
    /// The count changes because the two models disagree about grouping. A message carrying tool
    /// results becomes one `tool` message per result, since each one has to be addressed by its own
    /// `tool_call_id`; any images attached to that same message follow as a separate `user`
    /// message, because a `tool` message may only hold text. A message carrying tool calls becomes
    /// a single `assistant` message whose arguments are re-encoded as JSON strings, falling back to
    /// `{}` when the stored bytes are not valid UTF-8. Thinking blocks are dropped: this wire
    /// format has nowhere to put them.
    ///
    /// - Parameters:
    ///   - message: The message to convert.
    ///   - providerName: Vendor name embedded in unsupported-media errors.
    /// - Throws: `LLMError.mediaNotSupported` for video, documents, audio that is not WAV or MP3,
    ///   and audio supplied by URL or file reference — only inline base64 audio can be sent.
    package static func convert(
        _ message: LLMMessage,
        providerName: String
    ) throws -> [OpenAICompatibleMessage] {
        var result: [OpenAICompatibleMessage] = []

        // Each tool result travels as its own tool message, keyed by the id of the call it answers.
        let toolResults = message.toolResults
        if !toolResults.isEmpty {
            for toolResult in toolResults {
                result.append(OpenAICompatibleMessage(
                    role: "tool",
                    content: toolResult.content.contentValue,
                    toolCallId: toolResult.toolCallId,
                    toolCalls: nil
                ))
            }
            // A tool message holds text only, so images from the same message follow as a user message.
            let images = message.contents.compactMap { content -> ImageContent? in
                if case .image(let ic) = content { return ic }
                return nil
            }
            if !images.isEmpty {
                let parts = images.compactMap { convertImageToPart($0) }
                if !parts.isEmpty {
                    result.append(OpenAICompatibleMessage(
                        role: "user",
                        contentParts: parts,
                        toolCallId: nil,
                        toolCalls: nil
                    ))
                }
            }
            return result
        }

        // Tool calls collapse into one assistant message; arguments go out as a JSON string.
        let toolUses = message.toolUses
        if !toolUses.isEmpty {
            let toolCalls = toolUses.map { toolUse -> OpenAICompatibleMessageToolCall in
                let argumentsString: String
                if let str = String(data: toolUse.input, encoding: .utf8) {
                    argumentsString = str
                } else {
                    argumentsString = "{}"
                }
                return OpenAICompatibleMessageToolCall(
                    id: toolUse.id,
                    type: "function",
                    function: OpenAICompatibleMessageToolCallFunction(
                        name: toolUse.name,
                        arguments: argumentsString
                    )
                )
            }
            result.append(OpenAICompatibleMessage(
                role: "assistant",
                content: message.content.isEmpty ? nil : message.content,
                toolCallId: nil,
                toolCalls: toolCalls
            ))
            return result
        }

        // Media forces the multipart content form; plain text stays a single string.
        let hasMedia = message.contents.contains { content in
            switch content {
            case .image, .audio, .video, .document:
                return true
            default:
                return false
            }
        }

        let role = message.role == .user ? "user" : "assistant"

        if hasMedia {
            // Multimodal message: content becomes an array of typed parts.
            var contentParts: [OpenAICompatibleContentPart] = []

            for content in message.contents {
                switch content {
                case .text(let text):
                    contentParts.append(.text(text))

                case .image(let imageContent):
                    contentParts.append(convertImageToPart(imageContent))

                case .audio(let audioContent):
                    contentParts.append(try convertAudioToPart(audioContent, providerName: providerName))

                case .video:
                    throw LLMError.mediaNotSupported(mediaType: "video", provider: providerName)

                case .document:
                    throw LLMError.mediaNotSupported(mediaType: "document", provider: providerName)

                case .toolUse, .toolResult:
                    break

                case .thinking:
                    break
                }
            }

            result.append(OpenAICompatibleMessage(
                role: role,
                contentParts: contentParts,
                toolCallId: nil,
                toolCalls: nil
            ))
        } else {
            // Plain text message: content stays a bare string.
            result.append(OpenAICompatibleMessage(
                role: role,
                content: message.content,
                toolCallId: nil,
                toolCalls: nil
            ))
        }

        return result
    }

    /// Collapses a message down to its first text block.
    ///
    /// Everything else on the message is discarded — images, audio, tool calls, and tool results —
    /// and a message with no text at all becomes an empty string. Use `convert` for anything that
    /// has to survive the round trip.
    package static func convertSimple(_ message: LLMMessage) -> OpenAICompatibleMessage {
        let role = message.role == .user ? "user" : "assistant"
        let text = message.contents.compactMap { content -> String? in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.first ?? ""

        return OpenAICompatibleMessage(role: role, content: text, toolCallId: nil, toolCalls: nil)
    }

    // MARK: - Private Helpers

    private static func convertImageToPart(_ imageContent: ImageContent) -> OpenAICompatibleContentPart {
        imageContent.source.fold(
            base64: { .imageUrl(url: "data:\(imageContent.mimeType);base64,\($0.base64EncodedString())", detail: nil) },
            url: { .imageUrl(url: $0.absoluteString, detail: nil) },
            fileReference: { .imageUrl(url: $0, detail: nil) }
        )
    }

    private static func convertAudioToPart(
        _ audioContent: AudioContent,
        providerName: String
    ) throws -> OpenAICompatibleContentPart {
        switch audioContent.source {
        case .base64(let data):
            let format: String
            switch audioContent.mediaType {
            case .wav:
                format = "wav"
            case .mp3:
                format = "mp3"
            case .aac, .flac, .ogg, .aiff:
                throw LLMError.mediaNotSupported(mediaType: audioContent.mimeType, provider: providerName)
            }
            return .inputAudio(data: data.base64EncodedString(), format: format)

        case .url, .fileReference:
            throw LLMError.mediaNotSupported(mediaType: "audio (\(audioContent.source.sourceType))", provider: providerName)
        }
    }
}
