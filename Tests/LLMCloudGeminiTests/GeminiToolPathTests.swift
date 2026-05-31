import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini tool-call unified path")
struct GeminiToolPathTests {
    private let toolJSON = Data(#"""
    {
      "candidates": [
        {"content": {"role": "model", "parts": [
          {"text": "calling"},
          {"functionCall": {"name": "lookup", "args": {"q": "swift"}}}
        ]}, "finishReason": "STOP"}
      ],
      "usageMetadata": {"promptTokenCount": 4, "candidatesTokenCount": 2, "totalTokenCount": 6}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport) -> GeminiClient {
        GeminiClient(transport: transport, apiKey: "k", retryConfiguration: .disabled)
    }

    private var toolSet: ToolSet {
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }
        return ToolSet(tools: [lookup])
    }

    @Test("functionCall を ToolCall にパースし、tools/toolConfig を直列化")
    func parsesToolCallAndSerializes() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolJSON)
        }
        let response = try await client(mock).planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25, tools: toolSet, toolChoice: .required,
            systemPrompt: nil, temperature: nil, maxTokens: 200
        )

        #expect(response.text == "calling")
        #expect(response.toolCalls.count == 1)
        let call = try #require(response.toolCalls.first)
        #expect(call.name == "lookup")
        let args = try JSONDecoder().decode([String: String].self, from: call.arguments)
        #expect(args["q"] == "swift")

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("functionDeclarations"))
        #expect(sent.contains("functionCallingConfig"))
        #expect(sent.contains("ANY"))
    }
}
