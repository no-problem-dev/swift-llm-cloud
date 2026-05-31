import Foundation
import LLMClient

enum GeminiContentConverter {
    static func convert(_ message: LLMMessage) -> [GeminiContent] {
        let role = message.role == .user ? "user" : "model"
        var parts: [GeminiPart] = []
        var toolResultParts: [GeminiPart] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                parts.append(GeminiPart(text: text))
            case .toolUse(_, let name, let input):
                let args = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
                parts.append(GeminiPart(functionCall: GeminiFunctionCall(name: name, args: args)))
            case .toolResult(_, let name, let resultContent):
                let response: [String: Any] = ["result": resultContent.contentValue]
                toolResultParts.append(GeminiPart(functionResponse: GeminiFunctionResponse(name: name, response: response)))
            case .image(let imageContent):
                if let part = mediaPart(source: imageContent.source, mimeType: imageContent.mediaType) { parts.append(part) }
            case .audio(let audioContent):
                if let part = mediaPart(source: audioContent.source, mimeType: audioContent.mediaType) { parts.append(part) }
            case .video(let videoContent):
                if let part = mediaPart(source: videoContent.source, mimeType: videoContent.mediaType) { parts.append(part) }
            case .thinking:
                break
            }
        }

        var contents: [GeminiContent] = []
        if !parts.isEmpty { contents.append(GeminiContent(role: role, parts: parts)) }
        if !toolResultParts.isEmpty { contents.append(GeminiContent(role: "user", parts: toolResultParts)) }
        return contents
    }

    static func mediaPart<T: MediaType>(source: MediaSource, mimeType: T) -> GeminiPart? {
        switch source {
        case .base64(let data):
            return GeminiPart(inlineData: GeminiInlineData(mimeType: mimeType.mimeType, data: data.base64EncodedString()))
        case .url(let url):
            return GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: url.absoluteString))
        case .fileReference(let id):
            return GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: id))
        }
    }
}
