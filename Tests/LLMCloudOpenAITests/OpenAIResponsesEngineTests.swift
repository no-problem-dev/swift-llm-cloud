import Foundation
import Testing
import APIClient   // HTTPTransport(MockTransport/HTTPResponse) を再公開
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudOpenAI

/// `/v1/responses` を生 URLSession から contract(structured-data codec)経路へ統一した際の
/// ゴールデンパリティ検証。レスポンスボディは手書き init(from:)（複数 keyed container・
/// try? 型プローブ・StructuredValue）を持つため、structured-data デコードが Foundation
/// JSONDecoder と等価であることをフィクスチャで保証する。
@Suite("OpenAI Responses engine unified path")
struct OpenAIResponsesEngineTests {
    /// reasoning + function_call(arguments は JSON 文字列) + message + 詳細 usage を含む現実的な応答。
    private let fixture = Data(#"""
    {
      "id": "resp_1",
      "model": "gpt-5",
      "status": "completed",
      "output": [
        {"type":"reasoning","summary":[{"type":"summary_text","text":"thinking hard"}],"content":[]},
        {"type":"function_call","id":"fc_1","call_id":"call_abc","name":"lookup","arguments":"{\"q\":\"x\"}"},
        {"type":"message","content":[{"type":"output_text","text":"final answer"}]}
      ],
      "usage": {
        "input_tokens":10,"output_tokens":20,"total_tokens":30,
        "input_tokens_details":{"cached_tokens":4},
        "output_tokens_details":{"reasoning_tokens":7}
      }
    }
    """#.utf8)

    private func engine(_ transport: any HTTPTransport & HTTPStreamingTransport,
                        retry: RetryConfiguration = .default,
                        onRetry: RetryEventHandler? = nil) -> OpenAIResponsesEngine {
        OpenAIResponsesEngine(
            transport: transport, apiKey: "k",
            endpoint: URL(string: "https://api.openai.com/v1/responses")!,
            retryConfiguration: retry, retryEventHandler: onRetry
        )
    }

    private func runStep(_ engine: OpenAIResponsesEngine) async throws -> LLMResponse {
        try await engine.executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "gpt-5",
            systemPrompt: nil,
            tools: ToolSet(tools: []),
            toolChoice: nil,
            responseSchema: nil,
            reasoningEffort: .high,
            maxTokens: 256
        )
    }

    /// 比較しやすい正規化表現。
    private func normalize(_ r: LLMResponse) -> (model: String, stop: String, blocks: [String], usage: [Int]) {
        let blocks = r.content.map { block -> String in
            switch block {
            case .text(let t): return "text:\(t)"
            case .thinking(let t, _): return "thinking:\(t)"
            case .toolUse(let id, let name, let input):
                return "tool:\(id):\(name):\(String(decoding: input, as: UTF8.self))"
            case .image: return "image"
            case .audio: return "audio"
            }
        }
        let usage = [
            r.usage.inputTokens, r.usage.outputTokens,
            r.usage.reasoningTokens ?? -1, r.usage.cacheReadTokens ?? -1,
        ]
        return (r.model, "\(r.stopReason.map { "\($0)" } ?? "nil")", blocks, usage)
    }

    @Test("structured-data 経路のデコードが Foundation JSONDecoder と等価(ゴールデンパリティ)")
    func goldenParity() async throws {
        // OLD: 生 JSONDecoder（移行前の挙動）
        let oldBody = try JSONDecoder().decode(OpenAIResponsesResponseBody.self, from: fixture)
        let expected = normalize(OpenAIResponsesConverter.toLLMResponse(oldBody))

        // NEW: contract(structured-data) 経路
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: fixture)
        }
        let actual = normalize(try await runStep(engine(mock)))

        #expect(actual.model == expected.model)
        #expect(actual.stop == expected.stop)
        #expect(actual.blocks == expected.blocks)
        #expect(actual.usage == expected.usage)

        // 明示的な期待値（両経路が同じバグを共有しても検出できるように）
        #expect(actual.blocks == ["thinking:thinking hard", "tool:call_abc:lookup:{\"q\":\"x\"}", "text:final answer"])
        #expect(actual.usage == [10, 20, 7, 4])
        #expect(actual.stop == "toolUse")
    }

    @Test("tool_choice / max_output_tokens / reasoning を明示 CodingKeys のまま送信")
    func serializesRequest() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: fixture)
        }
        _ = try await runStep(engine(mock))
        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains("max_output_tokens"))
        #expect(sent.contains("\"store\""))
        #expect(sent.contains("\"effort\""))
        #expect(sent.contains("\"high\""))
        #expect(mock.recordedRequests.first?.headers["authorization"] == "Bearer k")
    }

    @Test("5xx は RetryRunner で再試行され、リトライ後に成功")
    func retriesThenSucceeds() async throws {
        let mock = MockTransport([
            .response(HTTPResponse(status: 500, headers: [:], body: Data(#"{"error":{"message":"boom"}}"#.utf8))),
            .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: fixture)),
        ])
        let response = try await runStep(engine(mock, retry: .custom(maxRetries: 3, baseDelay: 0.01, maxDelay: 0.02)))
        #expect(response.content.contains { if case .text(let t) = $0 { return t == "final answer" } else { return false } })
        #expect(mock.recordedRequests.count == 2)
    }
}
