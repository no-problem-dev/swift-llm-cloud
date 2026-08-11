import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GroqModel + OpenAICompatibleModelProtocol

extension GroqModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .groq(self) }
}

// MARK: - GroqClient

/// Client for models hosted on Groq's inference service, over its OpenAI-compatible API.
///
/// Structured output, chat, tool calls, and agent steps all come from the shared
/// `OpenAICompatibleEngine`; this type only pins the Groq endpoint. Models are `GroqModel`
/// values — the GPT-OSS, Llama, and Qwen builds Groq serves, all with a 131,072-token context
/// window, plus `.custom` for any other model ID. These are open-weight models that other vendors
/// host too, so choosing Groq buys inference latency rather than exclusive weights.
///
/// The output cap goes out as `max_completion_tokens`, the shared engine's default spelling, which
/// is what Groq expects.
///
/// Requests are never streamed: `streamAgentStep` falls back to the shared non-streaming
/// implementation and yields one completed event at the end rather than deltas.
///
/// Groq validates JSON schemas more strictly than OpenAI, and two of its rejections are pinned by
/// regression tests in this package. Schema keywords must stay camel case, so `additionalProperties`
/// is never snake-cased on the way out, and an object that declares `required` must also carry a
/// `properties` map even when the tool takes no arguments.
///
/// ## Example
///
/// ```swift
/// let client = GroqClient(apiKey: "gsk_...")
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .llama3_3_70b
/// )
/// ```
public struct GroqClient: OpenAICompatibleClientProtocol {
    public typealias Model = GroqModel

    package let engine: OpenAICompatibleEngine

    /// Full chat-completions URL used when the caller does not supply one.
    ///
    /// The API contract has an empty base path, so this URL is sent verbatim. A replacement must
    /// be a complete completions URL rather than a host, and must not end in a slash: Groq answers
    /// `Unknown request URL` for a trailing slash, and a regression test pins that this client
    /// never appends one.
    public static let defaultEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    /// Creates a client that authenticates with the given Groq API key.
    ///
    /// The key is sent as an `Authorization: Bearer` header. Retries are on by default (up to five
    /// after the first failure): retryable failures such as 429 and 5xx back off exponentially with
    /// jitter, except that a `Retry-After` or `x-ratelimit-reset-*` hint parsed from the response
    /// overrides the backoff curve. Those reset headers are read as durations with a unit suffix
    /// (`1.5s`, `800ms`), not as timestamps. Retries cover `generate` and `executeAgentStep`;
    /// `chat` and `planToolCalls` are sent exactly once.
    ///
    /// - Parameters:
    ///   - apiKey: Groq API key.
    ///   - endpoint: Replaces ``defaultEndpoint``; must be a complete chat-completions URL.
    ///   - session: Session backing the HTTP transport.
    ///   - retryConfiguration: Retry budget and backoff bounds. Pass `.disabled` to fail on the
    ///     first error.
    ///   - retryEventHandler: Called before each retry sleeps, with the attempt number, the error,
    ///     and the delay that was chosen.
    public init(
        apiKey: String,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.engine = OpenAICompatibleEngine(
            apiKey: apiKey,
            endpoint: endpoint ?? Self.defaultEndpoint,
            providerName: "Groq",
            session: session,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
