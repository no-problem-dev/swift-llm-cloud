import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - DeepSeekModel + OpenAICompatibleModelProtocol

extension DeepSeekModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .deepseek(self) }
}

// MARK: - DeepSeekClient

/// Client for DeepSeek's OpenAI-compatible chat completions API.
///
/// Structured output, chat, tool calls, and agent steps all come from the shared
/// `OpenAICompatibleEngine`; this type only pins the DeepSeek endpoint and the two request
/// quirks that separate DeepSeek from OpenAI. Models are `DeepSeekModel` values: `.v4Flash`,
/// `.v4Pro`, or `.custom` for any other model ID.
///
/// The output cap must be sent as `max_tokens` — DeepSeek does not accept OpenAI's
/// `max_completion_tokens` — and the completions path carries no `/v1` segment.
///
/// Requests are never streamed. Tool calling and JSON-schema structured output work through the
/// standard OpenAI-compatible fields, but `streamAgentStep` falls back to the shared
/// non-streaming implementation: it yields a single completed event at the end instead of text or
/// thinking deltas.
///
/// Token accounting follows OpenAI's shape, so the reported input count already includes cache
/// hits, and cache-read tokens are only broken out when the response carries
/// `prompt_tokens_details.cached_tokens`.
///
/// ## Example
///
/// ```swift
/// let client = DeepSeekClient(apiKey: "sk-...")
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .v4Flash
/// )
/// ```
public struct DeepSeekClient: OpenAICompatibleClientProtocol {
    public typealias Model = DeepSeekModel

    package let engine: OpenAICompatibleEngine

    /// Full chat-completions URL used when the caller does not supply one.
    ///
    /// The API contract has an empty base path, so this URL is sent verbatim. A replacement must
    /// therefore be a complete completions URL rather than a host, and must not end in a slash —
    /// a trailing slash is what made the sibling Groq endpoint answer `Unknown request URL`.
    /// DeepSeek's path has no `/v1` segment.
    public static let defaultEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    /// Creates a client that authenticates with the given DeepSeek API key.
    ///
    /// The key is sent as an `Authorization: Bearer` header. Retries are on by default (up to five
    /// after the first failure): retryable failures such as 429 and 5xx back off exponentially with
    /// jitter, except that a `Retry-After` or `x-ratelimit-reset-*` hint parsed from the response
    /// overrides the backoff curve. Retries cover `generate` and `executeAgentStep`; `chat` and
    /// `planToolCalls` are sent exactly once.
    ///
    /// - Parameters:
    ///   - apiKey: DeepSeek API key.
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
            providerName: "DeepSeek",
            session: session,
            // DeepSeek takes max_tokens; it does not accept max_completion_tokens.
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
