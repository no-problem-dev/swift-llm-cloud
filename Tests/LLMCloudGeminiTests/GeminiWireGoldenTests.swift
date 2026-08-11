import Foundation
import Testing
import LLMClient
@testable import LLMCloudGemini

/// Golden test pinning the exact JSON Gemini receives for each kind of message content.
///
/// Encoding uses `.sortedKeys` so key order is stable and the comparison can be a literal string.
/// No HTTP is involved, so a diff here means the request shape itself changed: whether a payload
/// is inlined as `inlineData` or referenced as `fileData`, how the MIME type is carried, and the
/// role each part is attached to.
@Suite("Gemini wire golden")
struct GeminiWireGoldenTests {
    private func encode(_ contents: [GeminiContent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(contents), as: UTF8.self)
    }

    private func convert(_ content: LLMMessage.MessageContent) throws -> String {
        try encode(GeminiContentConverter.convert(LLMMessage(role: .user, contents: [content])))
    }

    @Test("(a) text part")
    func textPart() throws {
        let json = try convert(.text("hello"))
        #expect(json == #"[{"parts":[{"text":"hello"}],"role":"user"}]"#)
    }

    @Test("(b) image base64 → inlineData")
    func imageBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try convert(.image(ImageContent(source: .base64(data), mediaType: .png)))
        #expect(json == #"[{"parts":[{"inlineData":{"data":"AQID","mime_type":"image\/png"}}],"role":"user"}]"#)
    }

    @Test("(c) image url → fileData")
    func imageURL() throws {
        let url = URL(string: "https://example.com/a.png")!
        let json = try convert(.image(ImageContent(source: .url(url), mediaType: .png)))
        #expect(json == #"[{"parts":[{"fileData":{"file_uri":"https:\/\/example.com\/a.png","mime_type":"image\/png"}}],"role":"user"}]"#)
    }

    @Test("(d) image fileReference → fileData")
    func imageFileReference() throws {
        let json = try convert(.image(ImageContent(source: .fileReference(id: "file_abc"), mediaType: .png)))
        #expect(json == #"[{"parts":[{"fileData":{"file_uri":"file_abc","mime_type":"image\/png"}}],"role":"user"}]"#)
    }

    @Test("(e) document pdf base64 → inlineData")
    func documentPDFBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try convert(.document(DocumentContent(source: .base64(data), mediaType: .pdf)))
        #expect(json == #"[{"parts":[{"inlineData":{"data":"AQID","mime_type":"application\/pdf"}}],"role":"user"}]"#)
    }

    @Test("(f) document fileReference → fileData")
    func documentFileReference() throws {
        let json = try convert(.document(DocumentContent(source: .fileReference(id: "file_doc"), mediaType: .pdf)))
        #expect(json == #"[{"parts":[{"fileData":{"file_uri":"file_doc","mime_type":"application\/pdf"}}],"role":"user"}]"#)
    }
}
