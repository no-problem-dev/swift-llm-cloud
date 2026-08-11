import Foundation
import Testing
import LLMClient
@testable import LLMCloudOpenAICompatible

/// Golden test pinning the exact JSON an OpenAI-compatible vendor receives for each content kind.
///
/// Encoding uses `.sortedKeys` so key order is stable and the comparison can be a literal string.
/// No HTTP is involved, so a diff here means the message shape itself changed: a base64 image
/// becoming a data URL, a file reference riding in `url` as a `file_id`, audio reaching
/// `input_audio`. Media the vendor cannot take must throw rather than be dropped, so a silent drop
/// shows up here as an unexpected success. Every vendor on this engine shares the conversion.
@Suite("OpenAICompatible wire golden")
struct OpenAICompatibleWireGoldenTests {
    private func encode(_ messages: [OpenAICompatibleMessage]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(messages), as: UTF8.self)
    }

    private func convert(_ content: LLMMessage.MessageContent) throws -> String {
        try encode(try OpenAICompatibleMessageConverter.convert(
            LLMMessage(role: .user, contents: [content]),
            providerName: "TestProvider"
        ))
    }

    @Test("(a) text message")
    func textMessage() throws {
        let json = try convert(.text("hello"))
        #expect(json == #"[{"content":"hello","role":"user"}]"#)
    }

    @Test("(b) image base64 → data URL")
    func imageBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try convert(.image(ImageContent(source: .base64(data), mediaType: .png)))
        #expect(json == #"[{"content":[{"image_url":{"url":"data:image\/png;base64,AQID"},"type":"image_url"}],"role":"user"}]"#)
    }

    @Test("(c) image url")
    func imageURL() throws {
        let url = URL(string: "https://example.com/a.png")!
        let json = try convert(.image(ImageContent(source: .url(url), mediaType: .png)))
        #expect(json == #"[{"content":[{"image_url":{"url":"https:\/\/example.com\/a.png"},"type":"image_url"}],"role":"user"}]"#)
    }

    @Test("(d) image fileReference → url=file_id")
    func imageFileReference() throws {
        let json = try convert(.image(ImageContent(source: .fileReference(id: "file_abc"), mediaType: .png)))
        #expect(json == #"[{"content":[{"image_url":{"url":"file_abc"},"type":"image_url"}],"role":"user"}]"#)
    }

    @Test("(e) document は mediaNotSupported を throw")
    func documentThrows() throws {
        #expect(throws: LLMError.self) {
            _ = try OpenAICompatibleMessageConverter.convert(
                LLMMessage(role: .user, contents: [.document(DocumentContent(source: .base64(Data([0x01])), mediaType: .pdf))]),
                providerName: "TestProvider"
            )
        }
    }

    @Test("(f) video は mediaNotSupported を throw")
    func videoThrows() throws {
        #expect(throws: LLMError.self) {
            _ = try OpenAICompatibleMessageConverter.convert(
                LLMMessage(role: .user, contents: [.video(VideoContent(source: .base64(Data([0x01])), mediaType: .mp4))]),
                providerName: "TestProvider"
            )
        }
    }

    @Test("(g) audio base64 wav → input_audio（silent skip でない）")
    func audioBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try convert(.audio(AudioContent(source: .base64(data), mediaType: .wav)))
        #expect(json == #"[{"content":[{"input_audio":{"data":"AQID","format":"wav"},"type":"input_audio"}],"role":"user"}]"#)
    }

    @Test("(h) 非対応 audio (url/未対応フォーマット) は throw（silent drop でない）")
    func audioUnsupportedThrows() throws {
        #expect(throws: LLMError.self) {
            _ = try OpenAICompatibleMessageConverter.convert(
                LLMMessage(role: .user, contents: [.audio(AudioContent(source: .url(URL(string: "https://e.com/a.wav")!), mediaType: .wav))]),
                providerName: "TestProvider"
            )
        }
        #expect(throws: LLMError.self) {
            _ = try OpenAICompatibleMessageConverter.convert(
                LLMMessage(role: .user, contents: [.audio(AudioContent(source: .base64(Data([0x01])), mediaType: .flac))]),
                providerName: "TestProvider"
            )
        }
    }
}
