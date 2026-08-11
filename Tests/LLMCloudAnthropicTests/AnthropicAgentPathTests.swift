import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

@Suite("Anthropic agent-step unified path")
struct AnthropicAgentPathTests {
    private let agentJSON = Data(#"""
    {
      "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-x",
      "content": [
        {"type":"thinking","text":"reasoning","signature":"sig1"},
        {"type":"text","text":"answer"},
        {"type":"tool_use","id":"tu_1","name":"lookup","input":{"q":"x"}}
      ],
      "stop_reason": "tool_use",
      "usage": {"input_tokens": 7, "output_tokens": 4}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .disabled,
                        onRetry: RetryEventHandler? = nil) -> AnthropicClient {
        AnthropicClient(transport: transport, apiKey: "k", retryConfiguration: retry, retryEventHandler: onRetry)
    }

    private var toolSet: ToolSet {
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }
        return ToolSet(tools: [lookup])
    }

    private var schema: JSONSchema {
        JSONSchema(type: .object, properties: ["a": JSONSchema(type: .string)], required: ["a"])
    }

    @Test("thinking ブロックを送信し、tools/output_config/beta を直列化、レスポンスを 3 ブロックにパース")
    func agentStepSerializesAndParses() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: agentJSON)
        }
        let priorThinking = LLMMessage(role: .assistant, contents: [.thinking(text: "earlier", signature: "s0"), .text("ok")])
        let response = try await client(mock).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi"), priorThinking],
            model: .sonnet, systemPrompt: nil, tools: toolSet, toolChoice: .auto,
            responseSchema: schema, thinkingMode: .disabled, reasoningEffort: nil, maxTokens: 300, cachePolicy: .implicit)

        let blocks = response.content
        #expect(blocks.count == 3)
        if case .thinking(let t, let sig) = blocks[0] { #expect(t == "reasoning"); #expect(sig == "sig1") } else { Issue.record("block0 not thinking") }
        if case .text(let t) = blocks[1] { #expect(t == "answer") } else { Issue.record("block1 not text") }
        if case .toolUse(let id, let name, _) = blocks[2] { #expect(id == "tu_1"); #expect(name == "lookup") } else { Issue.record("block2 not toolUse") }
        #expect(response.stopReason == .toolUse)

        let req = try #require(mock.recordedRequests.first)
        // Anthropic structured output is generally available, so no anthropic-beta header is sent.
        // Sending a stale beta name is an error response, not a silently ignored header.
        #expect(req.headers["anthropic-beta"] == nil)
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("\"thinking\""))
        #expect(sent.contains("earlier"))
        #expect(sent.contains("\"tools\""))
        #expect(sent.contains("input_schema"))
        #expect(sent.contains("output_config"))
    }

    @Test("5xx は RetryRunner で再試行され成功")
    func retriesThenSucceeds() async throws {
        let mock = MockTransport([
            .response(HTTPResponse(status: 500, headers: [:], body: Data(#"{"type":"error","error":{"type":"x","message":"boom"}}"#.utf8))),
            .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: agentJSON)),
        ])
        let response = try await client(mock, retry: .custom(maxRetries: 3, baseDelay: 0.01, maxDelay: 0.02)).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, systemPrompt: nil, tools: ToolSet(tools: []), toolChoice: nil,
            responseSchema: nil, thinkingMode: .disabled, reasoningEffort: nil, maxTokens: nil, cachePolicy: .implicit)
        #expect(response.content.count == 3)
        #expect(mock.recordedRequests.count == 2)
    }
}
