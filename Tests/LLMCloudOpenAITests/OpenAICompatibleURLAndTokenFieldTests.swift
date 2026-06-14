import Foundation
import Testing
import APIClient   // HTTPTransport(MockTransport/HTTPResponse) を再公開
import LLMClient
import LLMTool
import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// 回帰ゲート: OpenAI 互換系の URL 構築とトークンフィールド名を MockTransport で固定する。
///
/// - URL: 完全 URL を endpoint に持つ契約(path 空)で末尾スラッシュを付与しないこと
///   (Groq の `Unknown request URL` 障害の再発防止)。
/// - トークンフィールド: プロバイダーごとに max_completion_tokens / max_tokens を出し分けること
///   (Mistral の 422 障害の再発防止)。
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
        // JSON Schema キーワードは仕様どおり camelCase でなければならない。
        #expect(body.contains("\"additionalProperties\""))
        #expect(!body.contains("\"additional_properties\""))
    }

    @Test("引数なしツール: required があれば properties も出す(Groq の properties 欠落拒否再発防止)")
    func emptyObjectSchemaKeepsProperties() throws {
        // 引数なしツール相当: object + required(空)だが properties 無し。
        let schema = JSONSchema(type: .object, required: [])
        let adapted = OpenAISchemaAdapter().adapt(schema)
        // strict バリデータは required があるのに properties が無いと拒否するため、
        // 空でも properties を必ず持たせる。
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

/// 引数なしツール（list_remote_agents 相当）。inputSchema は空オブジェクト。
private struct NoArgTool: Tool {
    var toolName: String { "list_remote_agents" }
    var toolDescription: String { "list remote agents" }
    var inputSchema: JSONSchema { .object(properties: [:]) }
    var systemInstruction: String? { nil }
    func execute(with argumentsData: Data) async throws -> ToolResult { .text("ok") }
}
