import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

@Suite("Anthropic count_tokens adapter")
struct AnthropicCountTokensTests {

    // MARK: - Endpoint and response decoding

    @Test("/v1/messages/count_tokens を叩き input_tokens をデコード")
    func countsViaEndpoint() async throws {
        let mock = MockTransport(status: 200, body: Data(#"{"input_tokens":1234}"#.utf8))
        let client = AnthropicClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let n = try await client.tokenCounter.countInputTokens(
            modelID: "claude-sonnet-4-6",
            systemPrompt: "You are helpful.",
            messages: [LLMMessage.user("hi")],
            tools: nil
        )
        #expect(n == 1234)

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString.contains("/v1/messages/count_tokens"))
        #expect(req.headers["x-api-key"] == "k")
    }

    // MARK: - The counted payload must match what send would put on the wire
    //
    // A count is only useful if it measures the same bytes the real request carries, so messages,
    // system prompt, and tools all go through the same converters. The envelope differs, though:
    // count_tokens takes neither max_tokens nor stream.

    @Test("ボディは count_tokens 専用 envelope（max_tokens / stream を持たない）")
    func bodyOmitsCreateMessageEnvelope() async throws {
        let mock = MockTransport(status: 200, body: Data(#"{"input_tokens":10}"#.utf8))
        let client = AnthropicClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        _ = try await client.tokenCounter.countInputTokens(
            modelID: "claude-sonnet-4-6",
            systemPrompt: "S",
            messages: [LLMMessage.user("hi")],
            tools: nil
        )

        let req = try #require(mock.recordedRequests.first)
        let body = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(body.contains("\"messages\""))
        #expect(body.contains("\"system\""))
        #expect(!body.contains("max_tokens"))   // count_tokens rejects max_tokens as an unknown field
        #expect(!body.contains("\"stream\""))
    }

    @Test("tools は send と同一変換器 toAnthropicToolDefs でボディに入る")
    func toolsUseSameConverter() async throws {
        let mock = MockTransport(status: 200, body: Data(#"{"input_tokens":50}"#.utf8))
        let client = AnthropicClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let tool = DynamicTool("get_weather", description: "Get weather") {
            JSONSchema.string(description: "city").named("city")
        } handler: { _ in .text("ok") }
        let tools = ToolSet(tools: [tool])

        _ = try await client.tokenCounter.countInputTokens(
            modelID: "claude-sonnet-4-6",
            systemPrompt: nil,
            messages: [LLMMessage.user("weather?")],
            tools: tools
        )

        let req = try #require(mock.recordedRequests.first)
        let body = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(body.contains("get_weather"))
        #expect(body.contains("Get weather"))
        #expect(body.contains("input_schema"))
    }
}
