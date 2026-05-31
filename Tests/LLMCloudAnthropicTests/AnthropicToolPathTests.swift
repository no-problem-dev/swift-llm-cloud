import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

@Suite("Anthropic tool-call unified path")
struct AnthropicToolPathTests {
    private let toolUseJSON = Data(#"""
    {
      "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-x",
      "content": [
        {"type":"text","text":"calling"},
        {"type":"tool_use","id":"tu_1","name":"lookup","input":{"q":"swift"}}
      ],
      "stop_reason": "tool_use",
      "usage": {"input_tokens": 5, "output_tokens": 3}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport) -> AnthropicClient {
        AnthropicClient(transport: transport, apiKey: "k", retryConfiguration: .disabled)
    }

    private var toolSet: ToolSet {
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }
        return ToolSet(tools: [lookup])
    }

    @Test("tool_use ブロックを ToolCall にパースし、tools/tool_choice を直列化")
    func parsesToolCallAndSerializes() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolUseJSON)
        }
        let response = try await client(mock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: toolSet, toolChoice: .required,
            systemPrompt: nil, temperature: nil, maxTokens: 200
        )

        #expect(response.text == "calling")
        #expect(response.stopReason == .toolUse)
        #expect(response.toolCalls.count == 1)
        let call = try #require(response.toolCalls.first)
        #expect(call.id == "tu_1")
        #expect(call.name == "lookup")
        let args = try JSONDecoder().decode([String: String].self, from: call.arguments)
        #expect(args["q"] == "swift")

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("\"tools\""))
        #expect(sent.contains("input_schema"))
        #expect(sent.contains("tool_choice"))
        #expect(sent.contains("\"any\""))
        #expect(mock.recordedRequests.first?.headers["anthropic-beta"] == nil)
    }
}
