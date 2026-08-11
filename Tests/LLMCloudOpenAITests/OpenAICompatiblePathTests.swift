import Foundation
import Testing
import APIClient   // re-exports HTTPTransport, MockTransport, and HTTPResponse
import LLMClient
@testable import LLMCloudOpenAICompatible

/// Covers the plain send path after every request moved onto the contract, off a raw URLSession.
///
/// A mock transport captures what actually goes out: Bearer authorization, and
/// `max_completion_tokens` rather than the legacy `max_tokens`. It also checks that a 429 still
/// arrives as a decoded error carrying the vendor's message, since going through the contract
/// changes where the error body is parsed.
@Suite("OpenAICompatible unified HTTP path")
struct OpenAICompatiblePathTests {
    private let completionJSON = Data(#"""
    {"id":"1","object":"chat.completion","created":1,"model":"gpt-test",
     "choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],
     "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """#.utf8)

    private func provider(_ mock: MockTransport) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            transport: mock, apiKey: "k",
            endpoint: URL(string: "https://api.test/v1/chat/completions")!,
            providerName: "test"
        )
    }

    @Test("contract 経由で max_completion_tokens を送り(旧 max_tokens は送らない)、Bearer 認証を付与")
    func sendsModernRequest() async throws {
        let mock = MockTransport { _ in HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON) }
        let request = LLMRequest(
            model: .custom("gpt-test"),
            messages: [LLMMessage(role: .user, content: "hi")],
            systemPrompt: nil, responseSchema: nil, temperature: 0.5, maxTokens: 100
        )
        let (output, status, _) = try await provider(mock).sendRaw(request)
        #expect(status == 200)
        #expect(output.choices.first?.message.content == "hello")

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("max_completion_tokens"))
        #expect(!sent.contains("\"max_tokens\""))
        #expect(mock.recordedRequests.first?.headers["authorization"] == "Bearer k")
        #expect(mock.recordedRequests.first?.method == "POST")
    }

    @Test("429 は contract decodeError でリッチにマッピングされる")
    func richErrorMapping() async {
        let mock = MockTransport(status: 429, body: Data(#"{"error":{"message":"slow down","type":"rate_limit"}}"#.utf8))
        let request = LLMRequest(model: .custom("gpt-test"), messages: [LLMMessage(role: .user, content: "hi")])
        await #expect(throws: (any Error).self) {
            _ = try await provider(mock).sendRaw(request)
        }
    }
}
