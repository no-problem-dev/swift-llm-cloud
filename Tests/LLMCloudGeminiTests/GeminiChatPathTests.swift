import Foundation
import Testing
import APIClient
import LLMClient
import LLMChat
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudGemini

private struct Person: StructuredProtocol {
    let name: String
    let age: Int
    static var jsonSchema: JSONSchema {
        JSONSchema(type: .object, properties: ["name": JSONSchema(type: .string), "age": JSONSchema(type: .integer)], required: ["name", "age"])
    }
}

@Suite("Gemini chat unified path")
struct GeminiChatPathTests {
    private let responseJSON = Data(#"""
    {
      "candidates": [
        {"content": {"role": "model", "parts": [{"text": "{\"name\":\"Hana\",\"age\":29}"}]}, "finishReason": "STOP"}
      ],
      "usageMetadata": {"promptTokenCount": 11, "candidatesTokenCount": 6, "totalTokenCount": 17}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .disabled) -> GeminiClient {
        GeminiClient(transport: transport, apiKey: "k", retryConfiguration: retry)
    }

    @Test("contract 経由で structured output をデコードし、key クエリ認証と generationConfig を送信")
    func chatDecodesAndSends() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: responseJSON)
        }
        let response: ChatResponse<Person> = try await client(mock).chat(
            messages: [LLMMessage(role: .user, content: "who")],
            model: .flash25, systemPrompt: "sys", temperature: 0.2, maxTokens: 100
        )
        #expect(response.result.name == "Hana")
        #expect(response.result.age == 29)
        #expect(response.usage.inputTokens == 11)
        #expect(response.stopReason == .endTurn)

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["x-goog-api-key"] == "k")
        #expect(!req.url.absoluteString.contains("key=k"))
        #expect(req.url.absoluteString.contains(":generateContent"))
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("generationConfig"))
        #expect(sent.contains("responseSchema"))
        #expect(sent.contains("systemInstruction"))
    }

    @Test("429 は contract decodeError でリッチにマッピングされる")
    func richErrorMapping() async {
        let mock = MockTransport(status: 429, body: Data(#"{"error":{"code":429,"message":"slow","status":"RESOURCE_EXHAUSTED"}}"#.utf8))
        await #expect(throws: (any Error).self) {
            let _: ChatResponse<Person> = try await client(mock).chat(
                messages: [LLMMessage(role: .user, content: "who")],
                model: .flash25, systemPrompt: nil, temperature: nil, maxTokens: nil
            )
        }
    }
}
