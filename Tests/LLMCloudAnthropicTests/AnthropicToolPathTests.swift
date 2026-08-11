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
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)

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

    @Test("input_schema の JSON Schema キーワードは camelCase で出力される(snake_case 化回帰防止)")
    func schemaKeywordsNotSnakeCased() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolUseJSON)
        }
        // The .object factory adds additionalProperties: false by default, so the tool's schema
        // carries the camelCase keyword this test is watching.
        let tool = SchemaKeywordTool()
        _ = try await client(mock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: ToolSet(tools: [tool]), toolChoice: .auto,
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)
        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("\"additionalProperties\""))
        #expect(!sent.contains("additional_properties"))
    }
}

/// A tool whose input schema carries the additionalProperties keyword.
///
/// That keyword is what a snake_case key strategy would rewrite on its way to the wire, which
/// Anthropic then rejects as an invalid `input_schema`.
private struct SchemaKeywordTool: Tool {
    var toolName: String { "lookup" }
    var toolDescription: String { "look up" }
    var inputSchema: JSONSchema {
        .object(properties: ["q": .string(description: "query")], required: ["q"])
    }
    var systemInstruction: String? { nil }
    func execute(with argumentsData: Data) async throws -> ToolResult { .text("ok") }
}
