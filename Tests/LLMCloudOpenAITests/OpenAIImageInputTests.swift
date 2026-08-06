import Foundation
import LLMClient
import Testing
@testable import LLMCloudOpenAI

/// Responses API への画像入力の変換。
///
/// 形は実 API に投げて確かめたもの:
/// `{"role":"user","content":[{"type":"input_text",...},{"type":"input_image","image_url":"data:..."}]}`
@Suite("OpenAI Responses image input")
struct OpenAIImageInputTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47])

    private func encode(_ items: [OpenAIResponsesInputItem]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(items)
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("画像は input_image の data URI になる")
    func imageBecomesDataURI() throws {
        let message = LLMMessage(role: .user, contents: [
            .text("これは何の料理?"),
            .image(ImageContent(source: .base64(png), mediaType: .png)),
        ])
        let json = try encode(try OpenAIResponsesConverter.toInputItems([message]))

        #expect(json.count == 1)
        #expect(json[0]["role"] as? String == "user")
        let parts = try #require(json[0]["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "input_text")
        #expect(parts[0]["text"] as? String == "これは何の料理?")
        #expect(parts[1]["type"] as? String == "input_image")
        #expect(parts[1]["image_url"] as? String == "data:image/png;base64,\(png.base64EncodedString())")
    }

    /// テキストだけなら配列にしない。**既存の挙動を変えない**。
    @Test("テキストだけのメッセージは文字列のまま")
    func textOnlyStaysString() throws {
        let json = try encode(try OpenAIResponsesConverter.toInputItems([
            LLMMessage(role: .user, content: "hello"),
        ]))
        #expect(json[0]["content"] as? String == "hello")
    }

    @Test("URL 画像はそのまま image_url に入る")
    func urlImagePassesThrough() throws {
        let url = URL(string: "https://example.com/a.jpg")!
        let json = try encode(try OpenAIResponsesConverter.toInputItems([
            LLMMessage(role: .user, contents: [.image(ImageContent(source: .url(url), mediaType: .jpeg))]),
        ]))
        let parts = try #require(json[0]["content"] as? [[String: Any]])
        #expect(parts[0]["image_url"] as? String == "https://example.com/a.jpg")
    }

    @Test("Files API の画像は file_id で参照する")
    func fileReferenceUsesFileId() throws {
        let json = try encode(try OpenAIResponsesConverter.toInputItems([
            LLMMessage(role: .user, contents: [
                .image(ImageContent(source: .fileReference(id: "file-123"), mediaType: .png)),
            ]),
        ]))
        let parts = try #require(json[0]["content"] as? [[String: Any]])
        #expect(parts[0]["type"] as? String == "input_image")
        #expect(parts[0]["file_id"] as? String == "file-123")
    }

    /// 画像は**それが付いていた発言**に残る。別メッセージに切り離さない。
    @Test("複数の画像とテキストが 1 つのメッセージにまとまる")
    func multipleImagesStayInOneMessage() throws {
        let json = try encode(try OpenAIResponsesConverter.toInputItems([
            LLMMessage(role: .user, contents: [
                .text("2 枚あります"),
                .image(ImageContent(source: .base64(png), mediaType: .png)),
                .image(ImageContent(source: .base64(png), mediaType: .jpeg)),
            ]),
        ]))
        #expect(json.count == 1)
        let parts = try #require(json[0]["content"] as? [[String: Any]])
        #expect(parts.count == 3)
    }

    /// 画像のあとにツール呼び出しが来ても、画像が消えない。
    @Test("画像のあとの toolUse でメッセージが分かれる")
    func imageThenToolUseSplits() throws {
        let json = try encode(try OpenAIResponsesConverter.toInputItems([
            LLMMessage(role: .assistant, contents: [
                .text("見ます"),
                .image(ImageContent(source: .base64(png), mediaType: .png)),
                .toolUse(id: "call_1", name: "search", input: Data("{}".utf8)),
            ]),
        ]))
        #expect(json.count == 2)
        #expect(json[0]["content"] is [[String: Any]])
        #expect(json[1]["type"] as? String == "function_call")
    }

    /// 画像以外のメディアは Responses API に相当するものが無い。
    @Test("audio / video / document は今も未対応として弾く")
    func otherMediaStillThrows() {
        let audio = LLMMessage(role: .user, contents: [
            .audio(AudioContent(source: .base64(png), mediaType: .mp3)),
        ])
        #expect(throws: (any Error).self) {
            try OpenAIResponsesConverter.toInputItems([audio])
        }
    }
}
