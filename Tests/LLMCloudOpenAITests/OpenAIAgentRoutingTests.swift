import APIClient
import Foundation
import LLMClient
import LLMTool
import Testing
import HTTPTransport
@testable import LLMCloudOpenAI

/// Which OpenAI endpoint an agent step is routed to, and why the choice cannot depend on effort.
///
/// Chat Completions refuses function tools on a reasoning model:
///
/// > Function tools with reasoning_effort are not supported for gpt-5.6-luna
/// > in /v1/chat/completions. To use function tools, use /v1/responses
///
/// The refusal happens even when no `reasoning_effort` was sent, because those models reason by
/// default. Routing used to branch on whether an effort was supplied, so any call that left it
/// unset landed on Chat Completions and failed every time. The model's reasoning capability plus
/// the presence of tools is what decides, and ``routedURL(model:tools:effort:)`` reads the decision
/// off the URL the mock transport actually received.
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

    /// Runs one agent step and returns the URL the request was sent to.
    ///
    /// The call is deliberately `try?`: routing is decided before the response is parsed, so a
    /// decode failure on the canned body must not hide which endpoint was chosen.
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

    /// The regression this suite exists for: no effort supplied still routes to `/v1/responses`.
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

    /// Without tools there is nothing for Chat Completions to refuse, so it stays there.
    @Test("tools が無ければ Chat Completions のまま")
    func noToolsStaysOnChatCompletions() async throws {
        let url = try await routedURL(model: .gpt5_6Luna, tools: ToolSet(tools: []), effort: nil)
        #expect(url.contains("/chat/completions"))
    }

    /// A non-reasoning model is unaffected: tools on Chat Completions are fine there.
    @Test("非 reasoning モデルは tools ありでも Chat Completions")
    func nonReasoningModelStaysOnChatCompletions() async throws {
        let url = try await routedURL(model: .gpt4o, tools: toolSet, effort: nil)
        #expect(url.contains("/chat/completions"))
    }
}
