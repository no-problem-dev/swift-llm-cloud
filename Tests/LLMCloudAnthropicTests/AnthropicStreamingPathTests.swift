import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

@Suite("Anthropic streaming unified path")
struct AnthropicStreamingPathTests {
    private let sse = Data(#"""
    event: message_start
    data: {"type":"message_start","message":{"model":"claude-x","usage":{"input_tokens":5,"output_tokens":0}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"answer"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}

    event: message_stop
    data: {"type":"message_stop"}

    """#.utf8)

    @Test("SSE を transport 経由でストリームし、thinking/text デルタと completed を配信")
    func streamsDeltasAndCompletes() async throws {
        let mock = MockTransport(streamChunks: [sse])
        let client = AnthropicClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        var thinking = ""
        var text = ""
        var completed: LLMResponse?
        for try await event in client.streamAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, systemPrompt: nil, tools: ToolSet(tools: []), toolChoice: nil,
            responseSchema: nil, thinkingMode: .adaptive, reasoningEffort: nil, maxTokens: nil, cachePolicy: .implicit) {
            switch event {
            case .delta(let delta):
                switch delta {
                case .thinkingDelta(let t): thinking += t
                case .textDelta(let t): text += t
                default: break
                }
            case .completed(let response):
                completed = response
            }
        }

        #expect(thinking == "hmm")
        #expect(text == "answer")
        let response = try #require(completed)
        #expect(response.content.contains { if case .text(let t) = $0 { return t == "answer" } else { return false } })

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["accept"] == "text/event-stream")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("\"stream\""))
        #expect(sent.contains("thinking"))
        #expect(sent.contains("budget_tokens"))
    }
}
