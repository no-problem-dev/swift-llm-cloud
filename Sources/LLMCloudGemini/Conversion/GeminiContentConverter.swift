import Foundation
import LLMClient
import LLMCloudClient
import StructuredDataCore
import JSONParsing

/// Translates provider-neutral messages into Gemini turns.
enum GeminiContentConverter {
    /// Converts one message into the turns Gemini expects, which may be two rather than one.
    ///
    /// Gemini has only the `user` and `model` roles, and it requires tool results to arrive as
    /// `functionResponse` parts in a user turn. A message that mixes ordinary content with tool
    /// results therefore splits: the content keeps the message's own role, and the results follow
    /// as a separate user turn.
    ///
    /// Two details are specific to Gemini. Tool results are matched to their call by function
    /// name, not by id, so the call id is dropped here — instead it is read for the thought
    /// signature that has to ride back with a thinking model's `functionCall`. And thinking blocks
    /// are not replayed at all: the signature is the only reasoning state Gemini wants back.
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

    /// Wraps a media attachment as either inline base64 data or a file reference.
    ///
    /// Raw bytes become inline data; a URL or an uploaded file id becomes a file reference. Gemini
    /// treats both the same way once the part is built.
    static func mediaPart<T: MediaType>(source: MediaSource, mimeType: T) -> GeminiPart? {
        source.fold(
            base64: { GeminiPart(inlineData: GeminiInlineData(mimeType: mimeType.mimeType, data: $0.base64EncodedString())) },
            url: { GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: $0.absoluteString)) },
            fileReference: { GeminiPart(fileData: GeminiFileData(mimeType: mimeType.mimeType, fileUri: $0)) }
        )
    }
}
