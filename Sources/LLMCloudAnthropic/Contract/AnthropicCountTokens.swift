import APIContract
import Foundation
import LLMClient

// MARK: - Count Tokens Body

/// `/v1/messages/count_tokens` リクエストボディ。
///
/// **設計方針**: トークン数に影響する要素（model / system / messages / tools）のみを含み、
/// `max_tokens` / `stream` / `temperature` 等の **count_tokens が受け付けない / トークン数に無関係な
/// envelope フィールドは持たない**。
/// `messages` / `tools` は send パスと**同一の変換器**（`AnthropicMessageConverter` /
/// `ToolSet.toAnthropicToolDefs()`）が生成した型をそのまま用いる → 「数える内容 = 送る内容」を保証。
struct AnthropicCountTokensBody: Encodable, Sendable {
    let model: String
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicToolDef]?

    init(model: String, system: String?, messages: [AnthropicMessage], tools: [AnthropicToolDef]?) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
    }
}

// MARK: - Count Tokens Response

/// `/v1/messages/count_tokens` レスポンス。`{"input_tokens": N}`。
/// APIClient の keyStyle=.snakeCase により `input_tokens` → `inputTokens` へデコードされる。
struct AnthropicCountTokensResponse: Decodable, Sendable {
    let inputTokens: Int
}

// MARK: - Count Tokens Endpoint

extension AnthropicAPI {
    /// トークンカウントエンドポイント（`/v1/messages/count_tokens`）。
    struct CountTokens: APIContract, APIInput {
        typealias Group = AnthropicAPI
        typealias Input = Self
        typealias Output = AnthropicCountTokensResponse

        static let method: APIMethod = .post
        static let subPath: String = "/count_tokens"

        let beta: [String]
        let request: AnthropicCountTokensBody

        init(beta: [String] = [], request: AnthropicCountTokensBody) {
            self.beta = beta
            self.request = request
        }

        var pathParameters: [String: String] { [:] }
        var queryParameters: [String: String]? { nil }

        var additionalHeaders: [String: String] {
            var headers: [String: String] = [:]
            if !beta.isEmpty {
                headers["anthropic-beta"] = beta.joined(separator: ",")
            }
            return headers
        }

        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
            try encoder.encode(request)
        }

        static func decode(
            pathParameters: [String: String],
            queryParameters: [String: String],
            body: Data?,
            decoder: any APIBodyDecoder
        ) throws -> Self {
            fatalError("Client-only contract")
        }
    }
}
