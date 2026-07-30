import Foundation
import Testing
import APIClient
import LLMAgentStep
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini streaming agent-step unified path")
struct GeminiStreamingAgentPathTests {
    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport) -> GeminiClient {
        GeminiClient(transport: transport, apiKey: "k", retryConfiguration: .disabled)
    }

    private func collect(
        _ stream: AsyncThrowingStream<StreamingAgentEvent, Error>
    ) async throws -> (text: String, thinking: String, completed: [LLMResponse]) {
        var text = ""
        var thinking = ""
        var completed: [LLMResponse] = []
        for try await event in stream {
            switch event {
            case .delta(.textDelta(let t)): text += t
            case .delta(.thinkingDelta(let t)): thinking += t
            case .delta: break
            case .completed(let response): completed.append(response)
            }
        }
        return (text, thinking, completed)
    }

    private func streamAgentStep(
        _ client: GeminiClient,
        tools: ToolSet = ToolSet(tools: [])
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        client.streamAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25, systemPrompt: nil, tools: tools, toolChoice: nil,
            responseSchema: nil, thinkingMode: .disabled, reasoningEffort: nil,
            maxTokens: nil, cachePolicy: .implicit
        )
    }

    @Test("テキストデルタを到着順に配信し、EOF で完全レスポンスを 1 回だけ構築")
    func streamsTextDeltasAndCompletesOnEOF() async throws {
        let sse = Data(#"""
        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"こんに"}]}}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":2,"totalTokenCount":7}}

        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"ちは"}]}}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":4,"totalTokenCount":9}}

        data: {"candidates":[{"content":{"role":"model","parts":[]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":4,"totalTokenCount":9}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let result = try await collect(streamAgentStep(client(mock)))

        #expect(result.text == "こんにちは")
        #expect(result.completed.count == 1)
        let response = try #require(result.completed.first)
        #expect(response.content.count == 1)
        if case .text(let t) = response.content[0] { #expect(t == "こんにちは") } else { Issue.record("not text") }
        #expect(response.stopReason == .endTurn)
        // usage は累積値の上書き（最後のチャンクの値を採用）
        #expect(response.usage.inputTokens == 5)
        #expect(response.usage.outputTokens == 4)

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString.contains(":streamGenerateContent"))
        #expect(req.url.absoluteString.contains("alt=sse"))
        #expect(req.headers["accept"] == "text/event-stream")
    }

    @Test("functionCall は 1 チャンク完全体で toolUse ブロックになり、thoughtSignature が ID に埋め込まれる")
    func streamsFunctionCallWithThoughtSignature() async throws {
        let sse = Data(#"""
        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"探しています"}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"lookup","args":{"q":"x"}},"thoughtSignature":"sig-abc"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":6,"totalTokenCount":16}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }

        let result = try await collect(streamAgentStep(client(mock), tools: ToolSet(tools: [lookup])))

        #expect(result.text == "探しています")
        let response = try #require(result.completed.first)
        #expect(response.content.count == 2)
        if case .text(let t) = response.content[0] { #expect(t == "探しています") } else { Issue.record("block0 not text") }
        guard case .toolUse(let id, let name, let input) = response.content[1] else {
            Issue.record("block1 not toolUse")
            return
        }
        #expect(name == "lookup")
        #expect(String(decoding: input, as: UTF8.self).contains("\"q\":\"x\""))
        #expect(GeminiThoughtSignatureEncoding.decodeThoughtSignature(from: id) == "sig-abc")

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("functionDeclarations"))
    }

    @Test("複数 functionCall は到着順を保って蓄積される")
    func accumulatesMultipleFunctionCalls() async throws {
        let sse = Data(#"""
        data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"first","args":{}}}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"second","args":{}}}]},"finishReason":"STOP"}]}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let result = try await collect(streamAgentStep(client(mock)))

        let response = try #require(result.completed.first)
        let names: [String] = response.content.compactMap {
            if case .toolUse(_, let name, _) = $0 { return name } else { return nil }
        }
        #expect(names == ["first", "second"])
    }

    @Test("promptFeedback.blockReason は contentBlocked エラーとして throw される")
    func blockedPromptThrows() async throws {
        let sse = Data(#"""
        data: {"promptFeedback":{"blockReason":"SAFETY"}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        await #expect(throws: LLMError.self) {
            _ = try await collect(streamAgentStep(client(mock)))
        }
    }

    @Test("デルタもブロックもない空ストリームでも completed を 1 回返す（空コンテンツ）")
    func emptyStreamYieldsEmptyCompleted() async throws {
        let mock = MockTransport(streamChunks: [Data()])

        let result = try await collect(streamAgentStep(client(mock)))

        #expect(result.text.isEmpty)
        #expect(result.completed.count == 1)
        #expect(result.completed.first?.content.isEmpty == true)
    }
}
