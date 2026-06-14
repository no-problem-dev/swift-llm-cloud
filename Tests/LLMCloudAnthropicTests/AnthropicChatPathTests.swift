import Foundation
import Testing
import APIClient
import LLMClient
import LLMChat
@testable import LLMCloudClient
@testable import LLMCloudAnthropic

private struct Person: StructuredProtocol {
    let name: String
    let age: Int
    static var jsonSchema: JSONSchema {
        JSONSchema(type: .object, properties: ["name": JSONSchema(type: .string), "age": JSONSchema(type: .integer)], required: ["name", "age"])
    }
}

@Suite("Anthropic chat unified path")
struct AnthropicChatPathTests {
    private let responseJSON = Data(#"""
    {
      "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-x",
      "content": [{"type":"text","text":"{\"name\":\"Taro\",\"age\":35}"}],
      "stop_reason": "end_turn",
      "usage": {"input_tokens": 12, "output_tokens": 8}
    }
    """#.utf8)

    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .disabled) -> AnthropicClient {
        AnthropicClient(transport: transport, apiKey: "k", retryConfiguration: retry)
    }

    @Test("contract 経由で structured output をデコードし、x-api-key/beta ヘッダーを送信")
    func chatDecodesAndSendsHeaders() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: responseJSON)
        }
        let response: ChatResponse<Person> = try await client(mock).chat(
            messages: [LLMMessage(role: .user, content: "who")],
            model: .sonnet, systemPrompt: "sys", temperature: 0.3, maxTokens: 100
        )
        #expect(response.result.name == "Taro")
        #expect(response.result.age == 35)
        #expect(response.usage.inputTokens == 12)
        #expect(response.usage.outputTokens == 8)
        #expect(response.stopReason == .endTurn)
        #expect(response.model == "claude-x")

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["x-api-key"] == "k")
        #expect(req.headers["anthropic-version"] == "2023-06-01")
        // 構造化出力は GA。beta ヘッダーは送らない。
        #expect(req.headers["anthropic-beta"] == nil)
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("output_config"))
        #expect(sent.contains("max_tokens"))
    }

    @Test("429 は contract decodeError でリッチにマッピングされる")
    func richErrorMapping() async {
        let mock = MockTransport(status: 429, body: Data(#"{"type":"error","error":{"type":"rate_limit","message":"slow"}}"#.utf8))
        await #expect(throws: (any Error).self) {
            let _: ChatResponse<Person> = try await client(mock).chat(
                messages: [LLMMessage(role: .user, content: "who")],
                model: .sonnet, systemPrompt: nil, temperature: nil, maxTokens: nil
            )
        }
    }
}
