import Foundation
import Testing
import APIClient   // re-exports HTTPTransport, MockTransport, and HTTPResponse
import LLMClient
import LLMTool
import LLMCloudClient
import HTTPTransport
@testable import LLMCloudOpenAICompatible

/// Regression gate on the request URL and the token-limit field name for OpenAI-compatible vendors.
///
/// Both regressions were invisible in Swift and only showed up as a vendor error, so the outgoing
/// request is captured with a mock transport and inspected byte by byte:
/// - URL: a contract that carries a full URL in its endpoint and an empty path must not gain a
///   trailing slash. Groq answers `Unknown request URL` when it does.
/// - Token field: the parameter name is per vendor — `max_completion_tokens` for OpenAI, Groq, and
///   xAI, `max_tokens` for Mistral, DeepSeek, and OpenRouter. Mistral answers 422 on the wrong one.
///
/// The suite also pins tool-schema serialization, because Groq rejects a tool whose JSON Schema
/// keywords were snake_cased, or whose `required` arrives without a `properties` object.
@Suite("OpenAICompatible URL & token field regression")
struct OpenAICompatibleURLAndTokenFieldTests {
    private let completionJSON = Data(#"""
    {"id":"1","object":"chat.completion","created":1,"model":"m",
     "choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],
     "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """#.utf8)

    private func provider(
        endpoint: String,
        maxTokensParameter: OpenAICompatibleMaxTokensParameter,
        _ mock: MockTransport
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            transport: mock, apiKey: "k",
            endpoint: URL(string: endpoint)!,
            providerName: "test",
            maxTokensParameter: maxTokensParameter
        )
    }

    private func send(
        endpoint: String,
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens
    ) async throws -> (url: String, body: String) {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)
        }
        let request = LLMRequest(
            model: .custom("m"),
            messages: [LLMMessage(role: .user, content: "hi")],
            systemPrompt: nil, responseSchema: nil, temperature: nil, maxTokens: 100
        )
        _ = try await provider(endpoint: endpoint, maxTokensParameter: maxTokensParameter, mock).sendRaw(request)
        let recorded = try #require(mock.recordedRequests.first)
        return (recorded.url.absoluteString, String(decoding: try #require(recorded.body), as: UTF8.self))
    }

    @Test("完全 URL の endpoint に末尾スラッシュを付与しない(Groq 障害の再発防止)")
    func noTrailingSlash() async throws {
        let (groqURL, _) = try await send(endpoint: "https://api.groq.com/openai/v1/chat/completions")
        #expect(groqURL == "https://api.groq.com/openai/v1/chat/completions")
        #expect(!groqURL.hasSuffix("/"))

        let (openAIURL, _) = try await send(endpoint: "https://api.openai.com/v1/chat/completions")
        #expect(openAIURL == "https://api.openai.com/v1/chat/completions")
    }

    @Test("max_completion_tokens を使うプロバイダー(OpenAI/Groq/xAI)")
    func maxCompletionTokensField() async throws {
        let (_, body) = try await send(
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            maxTokensParameter: .maxCompletionTokens
        )
        #expect(body.contains("\"max_completion_tokens\""))
        #expect(!body.contains("\"max_tokens\""))
    }

    @Test("max_tokens を使うプロバイダー(Mistral/DeepSeek/OpenRouter)の 422 再発防止")
    func maxTokensField() async throws {
        let (_, body) = try await send(
            endpoint: "https://api.mistral.ai/v1/chat/completions",
            maxTokensParameter: .maxTokens
        )
        #expect(body.contains("\"max_tokens\""))
        #expect(!body.contains("\"max_completion_tokens\""))
    }

    @Test("tool スキーマの JSON Schema キーワードは snake_case 化されない(Groq の additionalProperties 拒否再発防止)")
    func toolSchemaKeywordsNotSnakeCased() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)
        }
        let tool = DynamicTool("read_file", description: "read a file") {
            JSONSchema.string(description: "path").named("path")
        } handler: { _ in .text("ok") }
        let engine = OpenAICompatibleEngine(
            transport: mock, apiKey: "k",
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            providerName: "Groq"
        )
        _ = try await engine.executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "llama-3.3-70b-versatile",
            systemPrompt: nil, tools: ToolSet(tools: [tool]), toolChoice: .auto,
            responseSchema: nil, reasoningEffort: nil, maxTokens: 256
        )
        let body = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        // JSON Schema keywords keep the camelCase the spec defines. The snake_case key strategy
        // applied to the rest of the request body must not reach inside a tool's schema.
        #expect(body.contains("\"additionalProperties\""))
        #expect(!body.contains("\"additional_properties\""))
    }

    @Test("引数なしツール: required があれば properties も出す(Groq の properties 欠落拒否再発防止)")
    func emptyObjectSchemaKeepsProperties() throws {
        // The shape a no-argument tool produces: an object with an empty required and no properties.
        let schema = JSONSchema(type: .object, required: [])
        let adapted = OpenAISchemaAdapter().adapt(schema)
        // A strict validator rejects a schema carrying required without properties, so the adapter
        // has to emit properties even when there is nothing in it.
        #expect(adapted.properties != nil)
        #expect(adapted.additionalProperties == false)
    }

    @Test("list_remote_agents 形(.object(properties:[:]))が serialize 時に properties を保持する")
    func emptyPropertiesObjectSerializesProperties() throws {
        let adapted = OpenAISchemaAdapter().adapt(.object(properties: [:]))
        let data = try Foundation.JSONEncoder().encode(WireSchema(adapted))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"properties\""))
        #expect(json.contains("\"additionalProperties\""))
    }

    @Test("引数なしツールを executeAgentStep で送ると tool params に properties が出る(end-to-end)")
    func noArgToolEndToEnd() async throws {
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: completionJSON)
        }
        let engine = OpenAICompatibleEngine(
            transport: mock, apiKey: "k",
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            providerName: "Groq"
        )
        _ = try await engine.executeAgentStep(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "llama-3.3-70b-versatile",
            systemPrompt: nil, tools: ToolSet(tools: [NoArgTool()]), toolChoice: .auto,
            responseSchema: nil, reasoningEffort: nil, maxTokens: 256
        )
        let body = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(body.contains("list_remote_agents"))
        #expect(body.contains("\"properties\""))
        #expect(body.contains("\"additionalProperties\""))
    }

    @Test("host 経路(planToolCalls)でも引数なしツールに properties が出る")
    func noArgToolViaPlanToolCalls() async throws {
        let toolCallJSON = Data(#"""
        {"id":"1","object":"chat.completion","created":1,"model":"m",
         "choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
        """#.utf8)
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: toolCallJSON)
        }
        let engine = OpenAICompatibleEngine(
            transport: mock, apiKey: "k",
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            providerName: "Groq"
        )
        _ = try await engine.planToolCalls(
            messages: [LLMMessage(role: .user, content: "hi")],
            modelId: "llama-3.3-70b-versatile",
            tools: ToolSet(tools: [NoArgTool()]), toolChoice: .auto,
            systemPrompt: nil, temperature: nil, maxTokens: 256
        )
        let body = String(decoding: try #require(mock.recordedRequests.first?.body), as: UTF8.self)
        #expect(body.contains("list_remote_agents"))
        #expect(body.contains("\"properties\""))
    }
}

/// A tool taking no arguments, modelled on the real `list_remote_agents`.
///
/// Its `inputSchema` is an empty object, which is the case that used to serialize without a
/// `properties` key and get rejected by Groq.
private struct NoArgTool: Tool {
    var toolName: String { "list_remote_agents" }
    var toolDescription: String { "list remote agents" }
    var inputSchema: JSONSchema { .object(properties: [:]) }
    var systemInstruction: String? { nil }
    func execute(with argumentsData: Data) async throws -> ToolResult { .text("ok") }
}
