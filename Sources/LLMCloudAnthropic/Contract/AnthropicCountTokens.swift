import APIContract
import Foundation
import LLMClient

// MARK: - Count Tokens Body

/// Request body for Anthropic's dedicated token counting endpoint.
///
/// It carries only what changes the count — model, system prompt, messages, and tool
/// definitions — and deliberately omits envelope fields such as `max_tokens`, `stream`, and
/// `temperature`, which the endpoint does not accept and which do not affect the input count.
///
/// The messages and tool definitions are produced by the same converters the send path uses, so
/// what is counted is byte-for-byte what would be sent. Building this body by hand would let the
/// estimate drift from the real request.
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

/// Reply from the token counting endpoint, which reports one number.
///
/// The body is a single `{"input_tokens": N}` object, whose snake_case key is mapped by the
/// client's key style. The count covers the input side only — there is no output figure, since
/// nothing has been generated.
struct AnthropicCountTokensResponse: Decodable, Sendable {
    let inputTokens: Int
}

// MARK: - Count Tokens Endpoint

extension AnthropicAPI {
    /// Anthropic's server-side token counter, reached at `/v1/messages/count_tokens`.
    ///
    /// This is a real network round trip that Anthropic tokenizes, not a local approximation, so
    /// the number matches what a send would be billed for on the input side. It costs latency
    /// and counts against the request rate limit, and it generates nothing.
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
