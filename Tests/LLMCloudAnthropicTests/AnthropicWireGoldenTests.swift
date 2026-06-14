import Foundation
import Testing
import LLMClient
@testable import LLMCloudAnthropic

/// MessageContent → ワイヤ JSON 変換のゴールデンテスト。
///
/// `JSONEncoder` のキー順を `.sortedKeys` で固定し、入力コンテンツに対する
/// 生成 JSON を期待文字列と比較する characterization テスト（HTTP 不要）。
@Suite("Anthropic wire golden")
struct AnthropicWireGoldenTests {
    private func encode(_ content: AnthropicMessageContent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(content), as: UTF8.self)
    }

    @Test("(a) text block")
    func textBlock() throws {
        let json = try encode(.text("hello"))
        #expect(json == #"{"text":"hello","type":"text"}"#)
    }

    @Test("(b) image base64")
    func imageBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try encode(.image(ImageContent(source: .base64(data), mediaType: .png)))
        #expect(json == #"{"source":{"data":"AQID","media_type":"image\/png","type":"base64"},"type":"image"}"#)
    }

    @Test("(c) image url")
    func imageURL() throws {
        let url = URL(string: "https://example.com/a.png")!
        let json = try encode(.image(ImageContent(source: .url(url), mediaType: .png)))
        #expect(json == #"{"source":{"type":"url","url":"https:\/\/example.com\/a.png"},"type":"image"}"#)
    }

    @Test("(d) image fileReference → file source")
    func imageFileReference() throws {
        let json = try encode(.image(ImageContent(source: .fileReference(id: "file_abc"), mediaType: .png)))
        #expect(json == #"{"source":{"file_id":"file_abc","type":"file"},"type":"image"}"#)
    }

    @Test("(e) document pdf base64")
    func documentPDFBase64() throws {
        let data = Data([0x01, 0x02, 0x03])
        let json = try encode(.document(DocumentContent(source: .base64(data), mediaType: .pdf)))
        #expect(json == #"{"source":{"data":"AQID","media_type":"application\/pdf","type":"base64"},"type":"document"}"#)
    }

    @Test("(f) document fileReference → file source")
    func documentFileReference() throws {
        let json = try encode(.document(DocumentContent(source: .fileReference(id: "file_doc"), mediaType: .pdf)))
        #expect(json == #"{"source":{"file_id":"file_doc","type":"file"},"type":"document"}"#)
    }

    @Test("file_id 参照を含むメッセージは files-api beta を付与")
    func betaValuesIncludesFilesAPIForFileReference() {
        let imageMsg = LLMMessage(role: .user, contents: [
            .image(ImageContent(source: .fileReference(id: "file_abc"), mediaType: .png))
        ])
        #expect(AnthropicProvider.betaValues(for: [imageMsg]) == ["files-api-2025-04-14"])

        let docMsg = LLMMessage(role: .user, contents: [
            .document(DocumentContent(source: .fileReference(id: "file_doc"), mediaType: .pdf))
        ])
        #expect(AnthropicProvider.betaValues(for: [docMsg]) == ["files-api-2025-04-14"])
    }

    @Test("base64/url のみのメッセージは beta を付与しない")
    func betaValuesEmptyForNonFileReference() {
        let msg = LLMMessage(role: .user, contents: [
            .image(ImageContent(source: .base64(Data([0x01])), mediaType: .png)),
            .text("hi")
        ])
        #expect(AnthropicProvider.betaValues(for: [msg]).isEmpty)
    }

    // MARK: - Prompt cache lowering

    private func encode(_ body: AnthropicRequestBody) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    private let userMessage = AnthropicMessage(role: "user", content: [.text("hi")])

    private func tool(_ name: String) -> AnthropicToolDef {
        AnthropicToolDef(name: name, description: "d", inputSchema: JSONSchema(type: .object))
    }

    @Test("(cache-a) explicitPrefix + system → system は配列形式で末尾に cache_control")
    func cacheExplicitPrefixWithSystem() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            system: "sys",
            maxTokens: 100,
            cachePolicy: .explicitPrefix(ttl: .seconds(300))
        )
        let json = try encode(body)
        #expect(json == #"{"max_tokens":100,"messages":[{"content":[{"text":"hi","type":"text"}],"role":"user"}],"model":"claude","system":[{"cache_control":{"ttl":"5m","type":"ephemeral"},"text":"sys","type":"text"}]}"#)
        #expect(body.cacheBetaValues.isEmpty)
    }

    @Test("(cache-b) explicitPrefix + system 無し + tools → 最後の tool に cache_control")
    func cacheExplicitPrefixWithToolsNoSystem() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            maxTokens: 100,
            tools: [tool("a"), tool("b")],
            cachePolicy: .explicitPrefix(ttl: .seconds(300))
        )
        let json = try encode(body)
        #expect(json == #"{"max_tokens":100,"messages":[{"content":[{"text":"hi","type":"text"}],"role":"user"}],"model":"claude","tools":[{"description":"d","input_schema":{"type":"object"},"name":"a"},{"cache_control":{"ttl":"5m","type":"ephemeral"},"description":"d","input_schema":{"type":"object"},"name":"b"}]}"#)
    }

    @Test("(cache-c) implicit → system は素の文字列で cache_control 無し（回帰防止）")
    func cacheImplicit() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            system: "sys",
            maxTokens: 100,
            tools: [tool("a")],
            cachePolicy: .implicit
        )
        let json = try encode(body)
        #expect(json == #"{"max_tokens":100,"messages":[{"content":[{"text":"hi","type":"text"}],"role":"user"}],"model":"claude","system":"sys","tools":[{"description":"d","input_schema":{"type":"object"},"name":"a"}]}"#)
        #expect(body.cacheBetaValues.isEmpty)
    }

    @Test("(cache-d) ttl 1h → ttl=\"1h\" かつ beta に extended-cache-ttl")
    func cacheExtendedTTL() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            system: "sys",
            maxTokens: 100,
            cachePolicy: .explicitPrefix(ttl: .seconds(3600))
        )
        let json = try encode(body)
        #expect(json == #"{"max_tokens":100,"messages":[{"content":[{"text":"hi","type":"text"}],"role":"user"}],"model":"claude","system":[{"cache_control":{"ttl":"1h","type":"ephemeral"},"text":"sys","type":"text"}]}"#)
        #expect(body.cacheBetaValues == ["extended-cache-ttl-2025-04-11"])
    }

    @Test("(cache-e) explicitPrefix + 対象不在（system/tools 無し）→ no-op で正当")
    func cacheExplicitPrefixNoTarget() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            maxTokens: 100,
            cachePolicy: .explicitPrefix(ttl: .seconds(300))
        )
        let json = try encode(body)
        #expect(json == #"{"max_tokens":100,"messages":[{"content":[{"text":"hi","type":"text"}],"role":"user"}],"model":"claude"}"#)
        #expect(body.cacheBetaValues.isEmpty)
    }

    @Test("(cache-f) tools に cache_control 付与時も 1h beta が出る")
    func cacheExtendedTTLOnTool() throws {
        let body = AnthropicRequestBody(
            model: "claude",
            messages: [userMessage],
            maxTokens: 100,
            tools: [tool("a")],
            cachePolicy: .explicitPrefix(ttl: .seconds(3600))
        )
        #expect(body.cacheBetaValues == ["extended-cache-ttl-2025-04-11"])
    }
}
