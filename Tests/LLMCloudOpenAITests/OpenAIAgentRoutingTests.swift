import APIClient
import Foundation
import LLMClient
import LLMTool
import Testing
@testable import LLMCloudOpenAI

/// `executeAgentStep` がどちらのエンドポイントへ行くか。
///
/// reasoning モデルに function tools を渡すと Chat Completions は拒否する:
///
/// > Function tools with reasoning_effort are not supported for gpt-5.6-luna
/// > in /v1/chat/completions. To use function tools, use /v1/responses
///
/// **`reasoning_effort` を送っていなくても拒否される。** 既定で reasoning する
/// ため。以前は effort の有無で振り分けていて、指定なしの呼び出し
/// (A2UI の副エージェント)が Chat Completions に落ちて毎回失敗していた。
@Suite("OpenAI agent step routing")
struct OpenAIAgentRoutingTests {
    private func transport() -> MockTransport {
        MockTransport { request in
            let body = request.url.absoluteString.contains("/responses")
                ? #"{"id":"r","model":"m","status":"completed","output":[],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#
                : #"{"id":"c","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
            return HTTPResponse(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
        }
    }

    private var toolSet: ToolSet {
        let render = DynamicTool("render", description: "render") {
            JSONSchema.string(description: "payload").named("x")
        } handler: { _ in .text("ok") }
        return ToolSet(tools: [render])
    }

    /// 叩かれた URL を返す。
    private func routedURL(
        model: GPTModel,
        tools: ToolSet,
        effort: ReasoningEffort?
    ) async throws -> String {
        let mock = transport()
        let client = OpenAIClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)
        _ = try? await client.executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            model: model,
            systemPrompt: nil,
            tools: tools,
            toolChoice: nil,
            responseSchema: nil,
            thinkingMode: .disabled,
            reasoningEffort: effort,
            maxTokens: nil,
            cachePolicy: .implicit
        )
        return try #require(mock.recordedRequests.first?.url.absoluteString)
    }

    /// これが今回の再発防止。effort を渡さなくても /v1/responses へ行く。
    @Test("reasoning モデル + tools は effort 無しでも /v1/responses")
    func reasoningModelWithToolsUsesResponses() async throws {
        let url = try await routedURL(model: .gpt5_6Luna, tools: toolSet, effort: nil)
        #expect(url.contains("/responses"))
    }

    @Test("effort を渡した場合も /v1/responses")
    func reasoningModelWithEffortUsesResponses() async throws {
        let url = try await routedURL(model: .gpt5_6Luna, tools: toolSet, effort: .low)
        #expect(url.contains("/responses"))
    }

    /// tools が無ければ Chat Completions で困らない。
    @Test("tools が無ければ Chat Completions のまま")
    func noToolsStaysOnChatCompletions() async throws {
        let url = try await routedURL(model: .gpt5_6Luna, tools: ToolSet(tools: []), effort: nil)
        #expect(url.contains("/chat/completions"))
    }

    /// reasoning しないモデルは従来どおり。
    @Test("非 reasoning モデルは tools ありでも Chat Completions")
    func nonReasoningModelStaysOnChatCompletions() async throws {
        let url = try await routedURL(model: .gpt4o, tools: toolSet, effort: nil)
        #expect(url.contains("/chat/completions"))
    }
}
