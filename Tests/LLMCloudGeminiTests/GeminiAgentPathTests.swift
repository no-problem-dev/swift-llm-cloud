import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini agent-step unified path")
struct GeminiAgentPathTests {
    private let agentJSON = Data(#"""
    {
      "candidates": [
        {"content": {"role": "model", "parts": [
          {"text": "answer"},
          {"functionCall": {"name": "lookup", "args": {"q": "x"}}}
        ]}, "finishReason": "STOP"}
      ],
      "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 3, "totalTokenCount": 8}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .disabled) -> GeminiClient {
        GeminiClient(transport: transport, apiKey: "k", retryConfiguration: retry)
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

    @Test("tools/responseSchema/thinkingConfig を直列化し、レスポンスを 2 ブロックにパース")
    func agentStepSerializesAndParses() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: agentJSON)
        }
        let response = try await client(mock).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25, systemPrompt: nil, tools: toolSet, toolChoice: .auto,
            responseSchema: schema, thinkingMode: .disabled, reasoningEffort: .medium, maxTokens: 300, cachePolicy: .implicit)

        let blocks = response.content
        #expect(blocks.count == 2)
        if case .text(let t) = blocks[0] { #expect(t == "answer") } else { Issue.record("block0 not text") }
        if case .toolUse(_, let name, _) = blocks[1] { #expect(name == "lookup") } else { Issue.record("block1 not toolUse") }

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("functionDeclarations"))
        #expect(sent.contains("responseSchema"))
        #expect(sent.contains("thinkingConfig"))
    }

    @Test("5xx は RetryRunner で再試行され成功")
    func retriesThenSucceeds() async throws {
        let mock = MockTransport([
            .response(HTTPResponse(status: 500, headers: [:], body: Data(#"{"error":{"code":500,"message":"boom","status":"INTERNAL"}}"#.utf8))),
            .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: agentJSON)),
        ])
        let response = try await client(mock, retry: .custom(maxRetries: 3, baseDelay: 0.01, maxDelay: 0.02)).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25, systemPrompt: nil, tools: ToolSet(tools: []), toolChoice: nil,
            responseSchema: nil, thinkingMode: .disabled, reasoningEffort: nil, maxTokens: nil, cachePolicy: .implicit)
        #expect(response.content.count == 2)
        #expect(mock.recordedRequests.count == 2)
    }
}
