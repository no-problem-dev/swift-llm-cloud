import Foundation
import Testing
import APIClient
import LLMClient
import LLMTool
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini 明示キャッシュ統合経路")
struct GeminiContextCachePathTests {

    private let generateJSON = Data(#"""
    {
      "candidates": [{"content": {"role": "model", "parts": [{"text": "answer"}]}, "finishReason": "STOP"}],
      "usageMetadata": {"promptTokenCount": 15000, "candidatesTokenCount": 10,
                        "totalTokenCount": 15010, "cachedContentTokenCount": 14000}
    }
    """#.utf8)

    private let cacheCreatedJSON = Data(#"""
    {"name": "cachedContents/cache-1", "model": "models/gemini-2.5-flash",
     "expireTime": "2099-01-01T00:00:00Z",
     "usageMetadata": {"totalTokenCount": 14000}}
    """#.utf8)

    private var toolSet: ToolSet {
        let lookup = DynamicTool("lookup", description: "look up") {
            JSONSchema.string(description: "query").named("q")
        } handler: { _ in .text("ok") }
        return ToolSet(tools: [lookup])
    }

    private func ok(_ body: Data) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body)
    }

    private func runStep(
        _ client: GeminiClient,
        policy: PromptCachePolicy = .explicitPrefix(ttl: .seconds(3600))
    ) async throws -> LLMResponse {
        try await client.executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: .flash25,
            systemPrompt: SystemPrompt(stringLiteral: "you are a researcher"),
            tools: toolSet,
            toolChoice: .auto,
            responseSchema: nil,
            thinkingMode: .disabled,
            reasoningEffort: nil,
            maxTokens: 256,
            cachePolicy: policy
        )
    }

    @Test("explicitPrefix: 初回は create → cachedContent 参照で generate、2 回目は再利用")
    func createsAndReusesCache() async throws {
        let mock = MockTransport { request in
            if request.url.path.contains("cachedContents") {
                return self.ok(self.cacheCreatedJSON)
            }
            return self.ok(self.generateJSON)
        }
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let first = try await runStep(client)
        #expect(first.usage.cacheReadTokens == 14000)

        _ = try await runStep(client)

        let cacheCreates = mock.recordedRequests.filter { $0.url.path.contains("cachedContents") && $0.method == "POST" }
        let generates = mock.recordedRequests.filter { $0.url.path.contains("generateContent") }
        #expect(cacheCreates.count == 1)
        #expect(generates.count == 2)

        // The create call is what carries the stable prefix: system instruction, tool declarations,
        // and the TTL.
        let createBody = String(decoding: cacheCreates[0].body ?? Data(), as: UTF8.self)
        #expect(createBody.contains("you are a researcher"))
        #expect(createBody.contains("functionDeclarations"))
        #expect(createBody.contains(#""ttl":"3600s""#))

        // Once cached, generate must reference cachedContent alone. Gemini rejects a request that
        // repeats the prefix fields alongside it.
        for generate in generates {
            let body = String(decoding: generate.body ?? Data(), as: UTF8.self)
            #expect(body.contains("cachedContents/cache-1"))
            #expect(!body.contains("systemInstruction"))
            #expect(!body.contains("functionDeclarations"))
        }
    }

    @Test("implicit: cachedContents API には一切触れない")
    func implicitPolicySkipsCacheAPI() async throws {
        let mock = MockTransport { request in
            #expect(!request.url.path.contains("cachedContents"))
            return self.ok(self.generateJSON)
        }
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)
        _ = try await runStep(client, policy: .implicit)

        let body = String(decoding: mock.recordedRequests[0].body ?? Data(), as: UTF8.self)
        #expect(body.contains("systemInstruction"))
        #expect(!body.contains("cachedContent\""))
    }

    @Test("最小トークン未満: inline へフォールバックし、以後 create を再試行しない")
    func belowMinimumFallsBackToInline() async throws {
        let belowMinJSON = Data(#"""
        {"error": {"code": 400, "status": "INVALID_ARGUMENT",
         "message": "The cached content is of 151 tokens. The minimum token count to start caching is 1024."}}
        """#.utf8)
        let mock = MockTransport { request in
            if request.url.path.contains("cachedContents") {
                return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: belowMinJSON)
            }
            return self.ok(self.generateJSON)
        }
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        _ = try await runStep(client)
        _ = try await runStep(client)

        let cacheCreates = mock.recordedRequests.filter { $0.url.path.contains("cachedContents") }
        #expect(cacheCreates.count == 1) // recorded as permanent for this prefix, so never retried

        let generates = mock.recordedRequests.filter { $0.url.path.contains("generateContent") }
        #expect(generates.count == 2)
        for generate in generates {
            let body = String(decoding: generate.body ?? Data(), as: UTF8.self)
            #expect(body.contains("systemInstruction")) // fell back to sending the prefix inline
            #expect(!body.contains("cachedContent\""))
        }
    }

    @Test("generate 時の失効 (403 CachedContent not found): 再作成 + 1 回リトライで回復")
    func recoversFromExpiredCache() async throws {
        let notFoundJSON = Data(#"""
        {"error": {"code": 403, "status": "PERMISSION_DENIED",
         "message": "CachedContent not found (or permission denied)."}}
        """#.utf8)
        let counter = Counter()
        let mock = MockTransport { request in
            if request.url.path.contains("cachedContents") {
                return self.ok(self.cacheCreatedJSON)
            }
            // Only the first generate fails as expired; the retry after re-creation succeeds.
            if counter.next() == 0 {
                return HTTPResponse(status: 403, headers: ["Content-Type": "application/json"], body: notFoundJSON)
            }
            return self.ok(self.generateJSON)
        }
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let response = try await runStep(client)
        #expect(response.usage.cacheReadTokens == 14000)

        let cacheCreates = mock.recordedRequests.filter { $0.url.path.contains("cachedContents") && $0.method == "POST" }
        let generates = mock.recordedRequests.filter { $0.url.path.contains("generateContent") }
        #expect(cacheCreates.count == 2) // initial create + re-create after the cache expired
        #expect(generates.count == 2)   // the 403 attempt + the retry that succeeded
    }

    @Test("releasePromptCaches: 作成済みリソースを DELETE する")
    func releaseDeletesResources() async throws {
        let mock = MockTransport { request in
            if request.url.path.contains("cachedContents") {
                if request.method == "DELETE" {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
                }
                return self.ok(self.cacheCreatedJSON)
            }
            return self.ok(self.generateJSON)
        }
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        _ = try await runStep(client)
        await client.releasePromptCaches()

        let deletes = mock.recordedRequests.filter { $0.method == "DELETE" }
        #expect(deletes.count == 1)
        #expect(deletes[0].url.path.contains("cache-1"))
    }

    @Test("キャッシュイベント: created → reused の順で発火")
    func emitsCacheEvents() async throws {
        let mock = MockTransport { request in
            request.url.path.contains("cachedContents") ? self.ok(self.cacheCreatedJSON) : self.ok(self.generateJSON)
        }
        let recorder = EventRecorder()
        let client = GeminiClient(
            transport: mock, apiKey: "k", retryConfiguration: .disabled,
            cacheEventHandler: { recorder.record($0) }
        )

        _ = try await runStep(client)
        _ = try await runStep(client)

        let events = recorder.events
        #expect(events.count == 2)
        if case .created(let name, let tokens) = events[0] {
            #expect(name == "cachedContents/cache-1")
            #expect(tokens == 14000)
        } else {
            Issue.record("first event is not .created")
        }
        if case .reused(let name) = events[1] {
            #expect(name == "cachedContents/cache-1")
        } else {
            Issue.record("second event is not .reused")
        }
    }
}

// MARK: - Test Helpers

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [GeminiCacheEvent] = []
    func record(_ event: GeminiCacheEvent) {
        lock.withLock { storage.append(event) }
    }
    var events: [GeminiCacheEvent] {
        lock.withLock { storage }
    }
}
