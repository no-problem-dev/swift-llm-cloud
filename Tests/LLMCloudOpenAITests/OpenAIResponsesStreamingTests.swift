import Foundation
import Testing
import APIClient
import LLMAgentStep
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudOpenAI

@Suite("OpenAI Responses streaming agent-step")
struct OpenAIResponsesStreamingTests {
    private func engine(_ transport: any HTTPTransport & HTTPStreamingTransport) -> OpenAIResponsesEngine {
        OpenAIResponsesEngine(
            transport: transport, apiKey: "k",
            endpoint: URL(string: "https://api.openai.com/v1/responses")!,
            retryConfiguration: .disabled
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<StreamingAgentEvent, Error>
    ) async throws -> (text: String, thinking: String, completed: [LLMResponse]) {
        var text = ""
        var thinking = ""
        var completed: [LLMResponse] = []
        for try await event in stream {
            switch event {
            case .delta(.textDelta(let t)): text += t
            case .delta(.thinkingDelta(let t)): thinking += t
            case .delta: break
            case .completed(let response): completed.append(response)
            }
        }
        return (text, thinking, completed)
    }

    private func streamStep(
        _ engine: OpenAIResponsesEngine,
        tools: ToolSet = ToolSet(tools: [])
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        engine.streamAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "gpt-5", systemPrompt: nil, tools: tools, toolChoice: nil,
            responseSchema: nil, reasoningEffort: nil, maxTokens: 256
        )
    }

    @Test("output_text.delta を転送し、response.completed の完全な Response を ground truth にする")
    func streamsTextDeltasAndUsesCompletedAsGroundTruth() async throws {
        let sse = Data(#"""
        data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_1","status":"in_progress","output":[]}}

        data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"type":"message"}}

        data: {"type":"response.output_text.delta","sequence_number":2,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"こんに"}

        data: {"type":"response.output_text.delta","sequence_number":3,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"ちは"}

        data: {"type":"response.output_text.done","sequence_number":4,"item_id":"msg_1","output_index":0,"content_index":0,"text":"こんにちは"}

        data: {"type":"response.completed","sequence_number":5,"response":{"id":"resp_1","model":"gpt-5","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"こんにちは"}]}],"usage":{"input_tokens":10,"output_tokens":4,"total_tokens":14}}}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let result = try await collect(streamStep(engine(mock)))

        #expect(result.text == "こんにちは")
        #expect(result.completed.count == 1)
        let response = try #require(result.completed.first)
        if case .text(let t) = response.content.first { #expect(t == "こんにちは") } else { Issue.record("not text") }
        #expect(response.usage.inputTokens == 10)
        #expect(response.usage.outputTokens == 4)

        let req = try #require(mock.recordedRequests.first)
        #expect(req.headers["accept"] == "text/event-stream")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains(#""stream":true"#))
    }

    @Test("function_call は completed の確定値から toolUse ブロックになる（引数デルタは解釈しない）")
    func functionCallComesFromCompletedResponse() async throws {
        let sse = Data(#"""
        data: {"type":"response.function_call_arguments.delta","sequence_number":1,"item_id":"fc_1","output_index":0,"delta":"{\"q\":"}

        data: {"type":"response.function_call_arguments.delta","sequence_number":2,"item_id":"fc_1","output_index":0,"delta":"\"x\"}"}

        data: {"type":"response.function_call_arguments.done","sequence_number":3,"item_id":"fc_1","output_index":0,"arguments":"{\"q\":\"x\"}"}

        data: {"type":"response.completed","sequence_number":4,"response":{"id":"resp_1","model":"gpt-5","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_abc","name":"lookup","arguments":"{\"q\":\"x\"}"}],"usage":{"input_tokens":5,"output_tokens":3,"total_tokens":8}}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }

        let result = try await collect(streamStep(engine(mock), tools: ToolSet(tools: [lookup])))

        #expect(result.text.isEmpty)
        let response = try #require(result.completed.first)
        guard case .toolUse(let id, let name, let input) = response.content.last else {
            Issue.record("expected toolUse, got \(response.content)")
            return
        }
        #expect(id == "call_abc")
        #expect(name == "lookup")
        #expect(String(decoding: input, as: UTF8.self) == #"{"q":"x"}"#)
    }

    @Test("reasoning summary のデルタは thinkingDelta として届く")
    func reasoningSummaryStreamsAsThinkingDelta() async throws {
        let sse = Data(#"""
        data: {"type":"response.reasoning_summary_text.delta","sequence_number":1,"item_id":"rs_1","output_index":0,"summary_index":0,"delta":"考え中"}

        data: {"type":"response.completed","sequence_number":2,"response":{"id":"resp_1","model":"gpt-5","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"答え"}]}]}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let result = try await collect(streamStep(engine(mock)))

        #expect(result.thinking == "考え中")
        #expect(result.completed.count == 1)
    }

    @Test("error イベントは throw され、以降のイベントは処理されない")
    func errorEventThrows() async throws {
        let sse = Data(#"""
        data: {"type":"error","sequence_number":1,"message":"boom","code":"server_error"}

        data: {"type":"response.completed","sequence_number":2,"response":{"id":"resp_1","output":[]}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        await #expect(throws: LLMError.self) {
            _ = try await collect(streamStep(engine(mock)))
        }
    }

    @Test("response.failed はエラーメッセージ付きで throw される")
    func failedResponseThrows() async throws {
        let sse = Data(#"""
        data: {"type":"response.failed","sequence_number":1,"response":{"id":"resp_1","status":"failed","output":[],"error":{"code":"server_error","message":"The model failed"}}}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        do {
            _ = try await collect(streamStep(engine(mock)))
            Issue.record("expected throw")
        } catch let error as LLMError {
            if case .serverError(_, let message) = error {
                #expect(message.contains("The model failed"))
            } else {
                Issue.record("unexpected error: \(error)")
            }
        }
    }
}
