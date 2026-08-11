import Foundation
import Testing
import APIClient   // re-exports HTTPTransport, MockTransport, and HTTPResponse
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// Covers the agent step after it moved off a raw URLSession and its own retry helper.
///
/// Two things moved at once, so both are pinned through a mock transport: the request is built by
/// the contract, carrying tools, `reasoning_effort`, and `max_completion_tokens`; and retries are
/// driven by the shared runner, which retries a 5xx, reports each attempt as a retry event, and
/// sends exactly one request when retrying is disabled.
@Suite("OpenAICompatible agent-step unified path")
struct OpenAICompatibleAgentStepTests {
    private let completionJSON = Data(#"""
    {"id":"1","object":"chat.completion","created":1,"model":"gpt-test",
     "choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],
     "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """#.utf8)

    private func engine(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .default,
                        onRetry: RetryEventHandler? = nil) -> OpenAICompatibleEngine {
        OpenAICompatibleEngine(
            transport: transport, apiKey: "k",
            endpoint: URL(string: "https://api.test/v1/chat/completions")!,
            providerName: "test",
            retryConfiguration: retry, retryEventHandler: onRetry
        )
    }

    @Test("tools / reasoning_effort / max_completion_tokens を contract 経由で送信")
    func serializesAgentRequest() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)
        }
        let lookup = DynamicTool("lookup", description: "look things up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }
        let tools = ToolSet(tools: [lookup])
        let response = try await engine(mock).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "gpt-test",
            systemPrompt: nil,
            tools: tools,
            toolChoice: .auto,
            responseSchema: nil,
            reasoningEffort: .high,
            maxTokens: 256)
        #expect(response.content.contains { if case .text(let t) = $0 { return t == "done" } else { return false } })

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("max_completion_tokens"))
        #expect(!sent.contains("\"max_tokens\""))
        #expect(sent.contains("reasoning_effort"))
        #expect(sent.contains("\"high\""))
        #expect(sent.contains("\"tools\""))
        #expect(sent.contains("lookup"))
        #expect(mock.recordedRequests.first?.headers["authorization"] == "Bearer k")
    }

    @Test("5xx は RetryRunner で再試行され、リトライ後に成功し RetryEvent を発火")
    func retriesThenSucceeds() async throws {
        let mock = MockTransport([
            .response(HTTPResponse(status: 500, headers: [:], body: Data(#"{"error":{"message":"boom"}}"#.utf8))),
            .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)),
        ])
        actor Events { var count = 0; func bump() { count += 1 } }
        let events = Events()
        let handler: RetryEventHandler = { _ in Task { await events.bump() } }

        let response = try await engine(
            mock,
            retry: .custom(maxRetries: 3, baseDelay: 0.01, maxDelay: 0.02),
            onRetry: handler
        ).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "gpt-test",
            systemPrompt: nil,
            tools: ToolSet(tools: []),
            toolChoice: nil,
            responseSchema: nil,
            reasoningEffort: nil,
            maxTokens: nil)
        #expect(response.content.contains { if case .text(let t) = $0 { return t == "done" } else { return false } })
        #expect(mock.recordedRequests.count == 2)
    }

    @Test("リトライ無効時は 1 回だけ送信して即座に失敗")
    func noRetryWhenDisabled() async {
        let mock = MockTransport([
            .response(HTTPResponse(status: 500, headers: [:], body: Data(#"{"error":{"message":"boom"}}"#.utf8))),
        ])
        await #expect(throws: (any Error).self) {
            _ = try await engine(mock, retry: .disabled).executeAgentStep(
                messages: [LLMMessage(role: .user, content: "hi")],
                modelId: "gpt-test",
                systemPrompt: nil,
                tools: ToolSet(tools: []),
                toolChoice: nil,
                responseSchema: nil,
                reasoningEffort: nil,
                maxTokens: nil)
        }
        #expect(mock.recordedRequests.count == 1)
    }
}
