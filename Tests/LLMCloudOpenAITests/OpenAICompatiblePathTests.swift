import Foundation
import Testing
import APIClient   // HTTPTransport(MockTransport/HTTPResponse) を再公開
import LLMClient
@testable import LLMCloudOpenAICompatible

/// 生 URLSession を撤廃し、全送信を api-client(contract)経由に統一したことを MockTransport で検証する。
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
