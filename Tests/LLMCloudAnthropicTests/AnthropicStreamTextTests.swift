import Foundation
import Testing
import APIClient
import LLMClient
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

@Suite("Anthropic streamText unified path")
struct AnthropicStreamTextTests {
    private let sse = Data(#"""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

    event: message_stop
    data: {"type":"message_stop"}

    """#.utf8)

    @Test("content_block_delta のテキストのみを transport SSE 経由で配信")
    func streamsTextChunks() async throws {
        let mock = MockTransport(streamChunks: [sse])
        let client = AnthropicClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        var text = ""
        for try await chunk in client.streamText(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .haiku, systemPrompt: "sys", temperature: 0.5, maxTokens: 100
        ) {
            text += chunk
        }
        #expect(text == "Hello world")

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["accept"] == "text/event-stream")
        #expect(req.headers["x-api-key"] == "k")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("\"stream\""))
    }
}
