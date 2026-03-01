import Foundation
import LLMClient

/// LLMMessage ↔ OpenAI 互換メッセージ変換
package enum OpenAICompatibleMessageConverter {

    /// LLMMessage を OpenAI 互換メッセージ形式に変換
    ///
    /// - Parameter message: 変換元の LLMMessage
    /// - Parameter providerName: プロバイダー名（エラーメッセージ用）
    /// - Returns: 変換された OpenAI 互換メッセージの配列
    /// - Throws: `LLMError.mediaNotSupported` 動画が含まれている場合
    package static func convert(
        _ message: LLMMessage,
        providerName: String
    ) throws -> [OpenAICompatibleMessage] {
        var result: [OpenAICompatibleMessage] = []

        // ツール結果を持つ場合、各結果を個別の tool メッセージとして送信
        let toolResults = message.toolResults
        if !toolResults.isEmpty {
            for toolResult in toolResults {
                result.append(OpenAICompatibleMessage(
                    role: "tool",
                    content: toolResult.content,
                    toolCallId: toolResult.toolCallId,
                    toolCalls: nil
                ))
            }
            // 同メッセージ内の画像を user メッセージとして追加
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

        // ツール呼び出しを持つ場合
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

        // メディアコンテンツを含むかチェック
        let hasMedia = message.contents.contains { content in
            switch content {
            case .image, .audio, .video:
                return true
            default:
                return false
            }
        }

        let role = message.role == .user ? "user" : "assistant"

        if hasMedia {
            // マルチモーダルメッセージ
            var contentParts: [OpenAICompatibleContentPart] = []

            for content in message.contents {
                switch content {
                case .text(let text):
                    contentParts.append(.text(text))

                case .image(let imageContent):
                    if let part = convertImageToPart(imageContent) {
                        contentParts.append(part)
                    }

                case .audio(let audioContent):
                    if let part = convertAudioToPart(audioContent) {
                        contentParts.append(part)
                    }

                case .video:
                    throw LLMError.mediaNotSupported(mediaType: "video", provider: providerName)

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
            // 通常のテキストメッセージ
            result.append(OpenAICompatibleMessage(
                role: role,
                content: message.content,
                toolCallId: nil,
                toolCalls: nil
            ))
        }

        return result
    }

    /// テキストのみの簡易変換（Chat 用）
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

    private static func convertImageToPart(_ imageContent: ImageContent) -> OpenAICompatibleContentPart? {
        let detail = imageContent.detail?.rawValue

        switch imageContent.source {
        case .base64(let data):
            let base64String = data.base64EncodedString()
            let dataUrl = "data:\(imageContent.mimeType);base64,\(base64String)"
            return .imageUrl(url: dataUrl, detail: detail)

        case .url(let url):
            return .imageUrl(url: url.absoluteString, detail: detail)

        case .fileReference(let id):
            return .imageUrl(url: id, detail: detail)
        }
    }

    private static func convertAudioToPart(_ audioContent: AudioContent) -> OpenAICompatibleContentPart? {
        switch audioContent.source {
        case .base64(let data):
            let base64String = data.base64EncodedString()
            let format: String
            switch audioContent.mediaType {
            case .wav:
                format = "wav"
            case .mp3:
                format = "mp3"
            case .aac, .flac, .ogg, .aiff:
                return nil
            }
            return .inputAudio(data: base64String, format: format)

        case .url, .fileReference:
            return nil
        }
    }
}
