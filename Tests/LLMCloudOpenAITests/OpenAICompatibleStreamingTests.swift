import Foundation
import Testing
import APIClient   // re-exports HTTPTransport, MockTransport, and HTTPResponse
import LLMAgentStep
import LLMClient
import LLMTool
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// Covers streaming on the shared OpenAI-compatible engine, which DeepSeek, Groq, Mistral,
/// OpenRouter, and xAI all inherit.
///
/// Before this existed the five fell through to `AgentCapableClient`'s default `streamAgentStep`,
/// which ran the call to completion and yielded exactly one `.completed` event — a stream in type
/// only, sending no `stream` field and parsing no SSE. Every test here therefore asserts on
/// ordering and event *count*, not just on the final text.
@Suite("OpenAICompatible streaming agent-step")
struct OpenAICompatibleStreamingTests {

    private func engine(_ transport: any HTTPTransport & HTTPStreamingTransport) -> OpenAICompatibleEngine {
        OpenAICompatibleEngine(
            transport: transport, apiKey: "k",
            endpoint: URL(string: "https://api.test/v1/chat/completions")!,
            providerName: "test",
            retryConfiguration: .disabled
        )
    }

    private func streamStep(
        _ engine: OpenAICompatibleEngine,
        tools: ToolSet = ToolSet(tools: [])
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        engine.streamAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "test-model", systemPrompt: nil, tools: tools, toolChoice: nil,
            responseSchema: nil, reasoningEffort: nil, maxTokens: 256
        )
    }

    /// Keeps every event so ordering and arity can be asserted, not just the concatenated text.
    private func collect(
        _ stream: AsyncThrowingStream<StreamingAgentEvent, Error>
    ) async throws -> [StreamingAgentEvent] {
        var events: [StreamingAgentEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - The defect

    /// The regression this whole file exists for: more than one event, deltas before the
    /// completion, and text that arrives in pieces rather than all at once.
    @Test("text deltas arrive one per frame, followed by a single completed event")
    func streamsTextDeltasInOrder() async throws {
        let sse = Data(#"""
        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"Hello"}}]}

        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":", "}}]}

        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"world"}}]}

        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: {"id":"1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12}}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        // Three text deltas plus one completion. The old default produced exactly one event.
        #expect(events.count == 4)

        let deltas: [String] = events.compactMap {
            if case .delta(.textDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(deltas == ["Hello", ", ", "world"])

        // Ordering: every delta precedes the completion.
        if case .completed = events.last {} else {
            Issue.record("Expected the last event to be .completed")
        }
        let completions = events.filter { if case .completed = $0 { return true } else { return false } }
        #expect(completions.count == 1)

        guard case .completed(let response) = events.last else { return }
        if case .text(let t) = response.content.first {
            #expect(t == "Hello, world")
        } else {
            Issue.record("Expected assembled text content")
        }
        #expect(response.stopReason == .endTurn)
        #expect(response.usage.inputTokens == 9)
        #expect(response.usage.outputTokens == 3)
        #expect(response.model == "test-model")
    }

    /// The request has to actually ask for a stream, and go out as SSE.
    @Test("the request sends stream:true and accepts text/event-stream")
    func requestsAStream() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"content":"hi"},"finish_reason":"stop"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        _ = try await collect(streamStep(engine(mock)))

        let request = try #require(mock.recordedRequests.first)
        #expect(request.headers["accept"] == "text/event-stream")
        let sent = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(sent.contains(#""stream":true"#))
        // stream_options is deliberately absent: Mistral defines no such parameter.
        #expect(!sent.contains("stream_options"))
    }

    /// The buffered path must not start announcing itself as a stream.
    @Test("the non-streaming agent step still sends no stream field")
    func bufferedStepOmitsStreamField() async throws {
        let completionJSON = Data(#"""
        {"id":"1","object":"chat.completion","created":1,"model":"test-model",
         "choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
        """#.utf8)
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)
        }

        _ = try await engine(mock).executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "test-model", systemPrompt: nil, tools: ToolSet(tools: []),
            toolChoice: nil, responseSchema: nil, reasoningEffort: nil, maxTokens: 256
        )

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(!sent.contains("\"stream\""))
    }

    // MARK: - Reasoning deltas

    /// DeepSeek and xAI name the field `reasoning_content`; OpenRouter names it `reasoning`.
    @Test("reasoning_content and reasoning both surface as thinking deltas")
    func streamsReasoningUnderEitherFieldName() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"reasoning_content":"Let me "}}]}

        data: {"id":"1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"reasoning":"think."}}]}

        data: {"id":"1","model":"deepseek-reasoner","choices":[{"index":0,"delta":{"content":"42"},"finish_reason":"stop"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        let thinking: [String] = events.compactMap {
            if case .delta(.thinkingDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(thinking == ["Let me ", "think."])

        // Reasoning is not folded into the visible answer.
        guard case .completed(let response) = try #require(events.last) else { return }
        if case .text(let t) = response.content.first {
            #expect(t == "42")
        } else {
            Issue.record("Expected assembled text content")
        }
    }

    // MARK: - Tool calls

    /// Tool calls arrive as fragments: the first carries id and name, the rest carry argument text.
    @Test("tool-call fragments are stitched back together by index")
    func assemblesToolCallsFromFragments() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"lookup","arguments":""}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"q\":"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"swift\"}"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        #expect(response.stopReason == .toolUse)
        #expect(response.content.count == 1)
        guard case .toolUse(let id, let name, let input) = try #require(response.content.first) else {
            Issue.record("Expected a toolUse block")
            return
        }
        #expect(id == "call_a")
        #expect(name == "lookup")
        #expect(String(decoding: input, as: UTF8.self) == #"{"q":"swift"}"#)
    }

    /// Two calls in one turn must not be merged into one.
    @Test("parallel tool calls stay separate and keep wire order")
    func keepsParallelToolCallsSeparate() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"first","arguments":"{\"a\":1}"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"second","arguments":"{\"b\":2}"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        let calls: [(String, String)] = response.content.compactMap {
            if case .toolUse(let id, let name, _) = $0 { return (id, name) } else { return nil }
        }
        #expect(calls.count == 2)
        #expect(calls.first?.0 == "call_a")
        #expect(calls.first?.1 == "first")
        #expect(calls.last?.0 == "call_b")
        #expect(calls.last?.1 == "second")
    }

    /// DeepSeek does not document `index` on streamed tool calls, and Groq and xAI do not document
    /// streamed tool calls at all, so a fragment without one still has to land somewhere sensible.
    @Test("tool-call fragments without an index are stitched by position")
    func assemblesToolCallsWithoutIndex() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"id":"call_a","type":"function","function":{"name":"lookup","arguments":"{\"q\":"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"tool_calls":[{"function":{"arguments":"\"swift\"}"}}]}}]}

        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        #expect(response.content.count == 1)
        guard case .toolUse(let id, let name, let input) = try #require(response.content.first) else {
            Issue.record("Expected a toolUse block")
            return
        }
        #expect(id == "call_a")
        #expect(name == "lookup")
        #expect(String(decoding: input, as: UTF8.self) == #"{"q":"swift"}"#)
    }

    // MARK: - Vendor deviations

    /// Mistral may send `delta.content` as an array of content chunks and `function.arguments` as a
    /// parsed JSON object. Decoding either as `String` throws, which would fail the whole frame.
    @Test("Mistral's structured content and object-valued arguments still decode")
    func handlesMistralStructuredShapes() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"mistral-large","choices":[{"index":0,"delta":{"content":[{"type":"text","text":"Bon"},{"type":"text","text":"jour"}]}}]}

        data: {"id":"1","model":"mistral-large","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"lookup","arguments":{"q":"swift","n":2}}}]}}]}

        data: {"id":"1","model":"mistral-large","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        let deltas: [String] = events.compactMap {
            if case .delta(.textDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(deltas == ["Bonjour"])

        guard case .completed(let response) = try #require(events.last) else { return }
        guard case .toolUse(_, _, let input) = try #require(response.content.last) else {
            Issue.record("Expected a toolUse block")
            return
        }
        // Re-serialized with sorted keys, so the arguments are stable JSON text.
        #expect(String(decoding: input, as: UTF8.self) == #"{"n":2,"q":"swift"}"#)
    }

    /// OpenRouter emits `: OPENROUTER PROCESSING` keepalives, and vendors send blank frames.
    /// Neither is a chunk, and neither may end the stream or throw.
    @Test("comment keepalives and blank frames are ignored")
    func ignoresKeepalivesAndBlankFrames() async throws {
        let sse = Data("""
        : OPENROUTER PROCESSING

        data: {"id":"1","model":"test-model","provider":"Anthropic","choices":[{"index":0,"delta":{"content":"a"}}]}

        : OPENROUTER PROCESSING

        data: {"id":"1","model":"test-model","provider":"Anthropic","choices":[{"index":0,"delta":{"content":"b"},"finish_reason":"stop","native_finish_reason":"end_turn"}]}

        data: [DONE]

        """.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        let deltas: [String] = events.compactMap {
            if case .delta(.textDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(deltas == ["a", "b"])
        #expect(events.count == 3)
    }

    /// A vendor extension in `finish_reason` must not be read as a clean end of turn.
    @Test("an unrecognized finish_reason reports no stop reason")
    func unknownFinishReasonIsNotEndTurn() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"deepseek-chat","choices":[{"index":0,"delta":{"content":"partial"},"finish_reason":"insufficient_system_resource"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        #expect(response.stopReason == nil)
    }

    /// A frame split across transport chunks mid-token must still parse. The SSE parser buffers
    /// bytes, so this pins that the engine does not assume one chunk equals one frame.
    @Test("a frame split across transport chunks is reassembled")
    func reassemblesSplitFrames() async throws {
        let whole = #"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"content":"こんにちは"},"finish_reason":"stop"}]}

        data: [DONE]

        """#
        let bytes = Array(whole.utf8)
        let split = bytes.count / 2
        let mock = MockTransport(streamChunks: [
            Data(bytes[..<split]),
            Data(bytes[split...]),
        ])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        if case .text(let t) = response.content.first {
            #expect(t == "こんにちは")
        } else {
            Issue.record("Expected assembled text content")
        }
    }

    /// A stream that stops before any finish_reason still hands back what did arrive, rather than
    /// throwing away a partial answer.
    @Test("a truncated stream yields the partial answer")
    func truncatedStreamYieldsPartialAnswer() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"content":"half an ans"}}]}

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])

        let events = try await collect(streamStep(engine(mock)))

        guard case .completed(let response) = try #require(events.last) else { return }
        if case .text(let t) = response.content.first {
            #expect(t == "half an ans")
        } else {
            Issue.record("Expected assembled text content")
        }
        #expect(response.stopReason == nil)
    }

    // MARK: - Errors

    /// A stream that breaks midway must fail the caller's loop rather than yield a `.completed`.
    ///
    /// Emitting a completion here would tell an agent loop that a truncated answer was the model's
    /// final one, and the loop would act on it. The deltas already delivered still stand.
    @Test("a mid-stream transport failure throws and yields no completion")
    func brokenStreamThrowsWithoutCompleting() async throws {
        struct FailingTransport: HTTPTransport, HTTPStreamingTransport, Sendable {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                HTTPResponse(status: 200, headers: [:], body: Data())
            }
            func stream(_ request: HTTPRequest) -> AsyncThrowingStream<Data, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(Data(#"""
                    data: {"id":"1","model":"test-model","choices":[{"index":0,"delta":{"content":"start"}}]}


                    """#.utf8))
                    continuation.finish(throwing: URLError(.networkConnectionLost))
                }
            }
        }

        var events: [StreamingAgentEvent] = []
        var thrown: (any Error)?
        do {
            for try await event in streamStep(engine(FailingTransport())) {
                events.append(event)
            }
        } catch {
            thrown = error
        }

        #expect(thrown != nil)
        let deltas: [String] = events.compactMap {
            if case .delta(.textDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(deltas == ["start"])
        #expect(!events.contains { if case .completed = $0 { return true } else { return false } })
    }

    /// A frame that is not JSON at all fails the stream rather than being skipped, so a vendor
    /// changing its wire format is loud instead of quietly truncating every answer.
    @Test("an undecodable frame fails the stream")
    func undecodableFrameThrows() async throws {
        let sse = Data("""
        data: {this is not json}

        data: [DONE]

        """.utf8)
        let mock = MockTransport(streamChunks: [sse])

        await #expect(throws: (any Error).self) {
            _ = try await collect(streamStep(engine(mock)))
        }
    }
}

// MARK: - Protocol dispatch

/// Stand-in for the five vendor clients: an engine and a model type, exactly what
/// ``OpenAICompatibleClientProtocol`` requires, with no `streamAgentStep` of its own.
///
/// DeepSeek, Groq, Mistral, OpenRouter, and xAI are each this and nothing more, so whatever
/// implementation this type resolves to is the one all five get.
private struct StandInCompatibleClient: OpenAICompatibleClientProtocol {
    struct Model: OpenAICompatibleModelProtocol {
        let id: String
        func toLLMModel() -> LLMModel { .custom(id) }
    }

    let engine: OpenAICompatibleEngine
}

/// Proves the five inherit real streaming rather than the protocol's run-to-completion default.
///
/// The call goes through the `AgentCapableClient` requirement, not through the concrete type, so
/// this is the same dispatch an agent loop holding `any AgentCapableClient` performs.
@Suite("OpenAICompatible clients inherit real streaming")
struct OpenAICompatibleClientStreamingDispatchTests {

    private func streamThroughProtocol<C: AgentCapableClient>(
        _ client: C,
        model: C.Model
    ) -> AsyncThrowingStream<StreamingAgentEvent, Error> {
        client.streamAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: model,
            systemPrompt: nil,
            tools: ToolSet(tools: []),
            toolChoice: nil,
            responseSchema: nil,
            thinkingMode: .disabled,
            reasoningEffort: nil,
            maxTokens: 256,
            cachePolicy: .implicit
        )
    }

    @Test("a vendor-shaped client streams deltas instead of one completed event")
    func vendorClientStreams() async throws {
        let sse = Data(#"""
        data: {"id":"1","model":"vendor-model","choices":[{"index":0,"delta":{"content":"one"}}]}

        data: {"id":"1","model":"vendor-model","choices":[{"index":0,"delta":{"content":" two"}}]}

        data: {"id":"1","model":"vendor-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """#.utf8)
        let mock = MockTransport(streamChunks: [sse])
        let client = StandInCompatibleClient(engine: OpenAICompatibleEngine(
            transport: mock, apiKey: "k",
            endpoint: URL(string: "https://api.test/v1/chat/completions")!,
            providerName: "vendor",
            retryConfiguration: .disabled
        ))

        var events: [StreamingAgentEvent] = []
        for try await event in streamThroughProtocol(client, model: .init(id: "vendor-model")) {
            events.append(event)
        }

        // The inherited default would have produced exactly one event.
        #expect(events.count == 3)
        let deltas: [String] = events.compactMap {
            if case .delta(.textDelta(let t)) = $0 { return t } else { return nil }
        }
        #expect(deltas == ["one", " two"])

        let sent = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(sent.contains(#""stream":true"#))
    }
}

// MARK: - Accumulator unit tests

/// Direct tests of the reassembly, independent of transport.
@Suite("OpenAICompatible stream accumulator")
struct OpenAICompatibleStreamAccumulatorTests {

    private func chunk(_ json: String) throws -> OpenAICompatibleStreamChunk {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAICompatibleStreamChunk.self, from: Data(json.utf8))
    }

    @Test("an empty stream produces a response with no content")
    func emptyStreamHasNoContent() {
        let accumulator = OpenAICompatibleStreamAccumulator()
        let response = accumulator.makeResponse(fallbackModel: "fallback")
        #expect(response.content.isEmpty)
        #expect(response.model == "fallback")
        #expect(response.usage.inputTokens == 0)
    }

    @Test("the model name falls back when no frame reports one")
    func modelFallsBack() throws {
        var accumulator = OpenAICompatibleStreamAccumulator()
        _ = accumulator.consume(try chunk(#"{"id":"1","choices":[{"index":0,"delta":{"content":"x"}}]}"#))
        #expect(accumulator.makeResponse(fallbackModel: "fallback").model == "fallback")
    }

    /// Vendors put usage on different frames, so the accumulator keeps the last non-null one rather
    /// than assuming it rides the final chunk.
    @Test("usage is taken from whichever frame reported it last")
    func usageTakesTheLastReportedValue() throws {
        var accumulator = OpenAICompatibleStreamAccumulator()
        _ = accumulator.consume(try chunk(#"""
        {"id":"1","model":"m","choices":[{"index":0,"delta":{"content":"a"}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
        """#))
        _ = accumulator.consume(try chunk(#"{"id":"1","model":"m","choices":[{"index":0,"delta":{"content":"b"}}]}"#))
        _ = accumulator.consume(try chunk(#"""
        {"id":"1","model":"m","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13}}
        """#))

        let response = accumulator.makeResponse(fallbackModel: "fallback")
        #expect(response.usage.inputTokens == 9)
        #expect(response.usage.outputTokens == 4)
    }

    /// A call whose name never arrived cannot be dispatched, so it must not reach the caller as a
    /// nameless tool request an agent loop would then try to run.
    @Test("a tool call that never got a name is dropped")
    func namelessToolCallIsDropped() throws {
        var accumulator = OpenAICompatibleStreamAccumulator()
        _ = accumulator.consume(try chunk(#"""
        {"id":"1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","function":{"arguments":"{}"}}]}}]}
        """#))

        #expect(accumulator.makeResponse(fallbackModel: "m").content.isEmpty)
    }

    @Test("a null content field contributes nothing")
    func nullContentIsIgnored() throws {
        var accumulator = OpenAICompatibleStreamAccumulator()
        let deltas = accumulator.consume(try chunk(#"""
        {"id":"1","model":"m","choices":[{"index":0,"delta":{"content":null,"role":null}}]}
        """#))
        #expect(deltas.isEmpty)
        #expect(accumulator.makeResponse(fallbackModel: "m").content.isEmpty)
    }
}
