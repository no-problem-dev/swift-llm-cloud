import Foundation
import Testing
import APIClient
import LLMClient
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini streamText unified path")
struct GeminiStreamTextTests {
    private let sse = Data(#"""
    data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

    data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}

    """#.utf8)

    @Test("streamGenerateContent の text を transport SSE 経由で配信")
    func streamsTextChunks() async throws {
        let mock = MockTransport(streamChunks: [sse])
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        var text = ""
        for try await chunk in client.streamText(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25, systemPrompt: "sys", temperature: 0.5, maxTokens: 100
        ) {
            text += chunk
        }
        #expect(text == "Hello world")

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["accept"] == "text/event-stream")
        #expect(req.url.absoluteString.contains(":streamGenerateContent"))
        #expect(req.url.absoluteString.contains("alt=sse"))
        #expect(req.headers["x-goog-api-key"] == "k")
        #expect(!req.url.absoluteString.contains("key=k"))
    }
}
