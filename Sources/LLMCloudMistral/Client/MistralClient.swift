import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - MistralModel + OpenAICompatibleModelProtocol

extension MistralModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .mistral(self) }
}

// MARK: - MistralClient

/// Client for the Mistral AI chat completions API.
///
/// Structured output, chat, tool calls, and agent steps all come from the shared
/// `OpenAICompatibleEngine`; this type only pins the Mistral endpoint and the one request quirk
/// that separates Mistral from OpenAI. Models are `MistralModel` values — `.small`, `.medium`,
/// `.large`, the code-focused `.codestral`, the lightweight `.ministral8b`, or `.custom` for any
/// other model ID. Their context windows differ widely, from 32K on `.small` to 256K on
/// `.codestral`. Most cases resolve to a `-latest` alias rather than a dated build, so the weights
/// behind them can change without a release here; `.ministral8b` is the exception and is pinned to
/// a specific build.
///
/// The output cap must be sent as `max_tokens`: Mistral rejects OpenAI's `max_completion_tokens`
/// with `422 Extra inputs are not permitted`, and a regression test pins the spelling.
///
/// Requests are never streamed: `streamAgentStep` falls back to the shared non-streaming
/// implementation and yields one completed event at the end rather than deltas.
///
/// ## Example
///
/// ```swift
/// let client = MistralClient(apiKey: "...")
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .large
/// )
/// ```
public struct MistralClient: OpenAICompatibleClientProtocol {
    public typealias Model = MistralModel

    package let engine: OpenAICompatibleEngine

    /// Full chat-completions URL used when the caller does not supply one.
    ///
    /// The API contract has an empty base path, so this URL is sent verbatim. A replacement must
    /// be a complete completions URL rather than a host, and must not end in a slash — a trailing
    /// slash is what made the sibling Groq endpoint answer `Unknown request URL`.
    public static let defaultEndpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!

    /// Creates a client that authenticates with the given Mistral API key.
    ///
    /// The key is sent as an `Authorization: Bearer` header. Retries are on by default (up to five
    /// after the first failure): retryable failures such as 429 and 5xx back off exponentially with
    /// jitter, except that a `Retry-After` or `x-ratelimit-reset-*` hint parsed from the response
    /// overrides the backoff curve. A 422 from an unsupported field is not retryable and surfaces
    /// immediately. Retries cover `generate` and `executeAgentStep`; `chat` and `planToolCalls` are
    /// sent exactly once.
    ///
    /// - Parameters:
    ///   - apiKey: Mistral API key.
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
            providerName: "Mistral",
            session: session,
            // Mistral rejects max_completion_tokens with a 422; only max_tokens is accepted.
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
