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

    // MARK: - ToolChoice の全ケースがワイヤに出る
    //
    // 以前 .disabled は init で .none に写されたあと encode で .auto に畳まれ、
    // {"type":"auto"} として送られていた。tools も付いたままなので、
    // 「ツールを封じたつもりの最終ターン」でモデルが平然とツールを呼べてしまう。

    /// 送られたリクエストボディの tool_choice を素の JSON として取り出す。
    private func sentToolChoice(_ mock: MockTransport) throws -> [String: String] {
        let body = try #require(mock.recordedRequests.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(json["tool_choice"] as? [String: String])
    }

    private func sentHasTools(_ mock: MockTransport) throws -> Bool {
        let body = try #require(mock.recordedRequests.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return (json["tools"] as? [Any])?.isEmpty == false
    }

    @Test("ToolChoice.disabled は tool_choice を none で送る")
    func disabledSendsNone() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolUseJSON)
        }
        _ = try await client(mock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: toolSet, toolChoice: .disabled,
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)

        #expect(try sentToolChoice(mock) == ["type": "none"])
        // 定義そのものは残す。封じるのと引っ込めるのは別で、引っ込めるとキャッシュ前置が壊れる。
        #expect(try sentHasTools(mock))
    }

    @Test("ToolChoice.auto は tool_choice を auto で送る")
    func autoSendsAuto() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolUseJSON)
        }
        _ = try await client(mock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: toolSet, toolChoice: .auto,
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)

        #expect(try sentToolChoice(mock) == ["type": "auto"])
    }

    @Test("ToolChoice.required は any、.tool(name) は tool+name")
    func requiredAndNamedToolSerialize() async throws {
        let makeMock = {
            MockTransport { _ in
                HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: self.toolUseJSON)
            }
        }

        let requiredMock = makeMock()
        _ = try await client(requiredMock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: toolSet, toolChoice: .required,
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)
        #expect(try sentToolChoice(requiredMock) == ["type": "any"])

        let namedMock = makeMock()
        _ = try await client(namedMock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, tools: toolSet, toolChoice: .tool("lookup"),
            systemPrompt: nil, temperature: nil, maxTokens: 200, cachePolicy: .implicit)
        #expect(try sentToolChoice(namedMock) == ["type": "tool", "name": "lookup"])
    }

    @Test("エージェントステップでも .disabled は none で送る")
    func agentStepHonoursDisabled() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolUseJSON)
        }
        _ = try await client(mock).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .sonnet, systemPrompt: nil, tools: toolSet, toolChoice: .disabled,
            responseSchema: nil, thinkingMode: .disabled, reasoningEffort: nil,
            maxTokens: 200, cachePolicy: .implicit)

        #expect(try sentToolChoice(mock) == ["type": "none"])
        #expect(try sentHasTools(mock))
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
