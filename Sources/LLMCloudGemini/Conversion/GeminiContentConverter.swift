import Foundation
import LLMClient
import LLMCloudClient
import StructuredDataCore
import JSONParsing

enum GeminiContentConverter {
    static func convert(_ message: LLMMessage) -> [GeminiContent] {
        let role = message.role == .user ? "user" : "model"
        var parts: [GeminiPart] = []
        var toolResultParts: [GeminiPart] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                parts.append(GeminiPart(text: text))
            case .toolUse(let id, let name, let input):
                let args = try? JSONParser().parse(input)
                let signature = GeminiThoughtSignatureEncoding.decodeThoughtSignature(from: id)
                parts.append(GeminiPart(functionCall: GeminiFunctionCall(name: name, args: args), thoughtSignature: signature))
            case .toolResult(_, let name, let resultContent):
                let response: GeminiJSONValue = .object(["result": .string(resultContent.contentValue)])
                toolResultParts.append(GeminiPart(functionResponse: GeminiFunctionResponse(name: name, response: response)))
            case .image(let imageContent):
                if let part = mediaPart(source: imageContent.source, mimeType: imageContent.mediaType) { parts.append(part) }
            case .audio(let audioContent):
                if let part = mediaPart(source: audioContent.source, mimeType: audioContent.mediaType) { parts.append(part) }
            case .video(let videoContent):
                if let part = mediaPart(source: videoContent.source, mimeType: videoContent.mediaType) { parts.append(part) }
            case .document(let documentContent):
                if let part = mediaPart(source: documentContent.source, mimeType: documentContent.mediaType) { parts.append(part) }
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
        source.fold(
            base64: { GeminiPart(inlineData: GeminiInlineData(mimeType: mimeType.mimeType, data: $0.base64EncodedString())) },
            url: { GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: $0.absoluteString)) },
            fileReference: { GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: $0)) }
        )
    }
}
