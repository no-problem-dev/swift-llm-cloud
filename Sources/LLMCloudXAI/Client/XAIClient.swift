import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GrokModel + OpenAICompatibleModelProtocol

extension GrokModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .grok(self) }
}

// MARK: - XAIClient

/// Client for xAI's Grok chat completions API.
///
/// Structured output, chat, tool calls, and agent steps all come from the shared
/// `OpenAICompatibleEngine`; this type only pins the xAI endpoint. Models are `GrokModel`
/// values — `.grok43`, the three Grok 4.20 variants, the coding-focused `.grokBuild`, or `.custom`
/// for any other model ID.
///
/// Reasoning is selected by model ID rather than by a request field: `.grok420Reasoning` and
/// `.grok420NonReasoning` are two distinct model IDs of the same generation. `executeAgentStep`
/// additionally forwards a caller-supplied reasoning effort as `reasoning_effort`, and never sends
/// `temperature`, so a reasoning model keeps its own sampling defaults during an agent loop;
/// `generate` and `chat` do forward `temperature` when given one.
///
/// The output cap goes out as `max_completion_tokens`, the shared engine's default spelling, which
/// is what the Grok 4 reasoning models require.
///
/// `streamAgentStep` streams for real: the request goes out with `stream: true` and the SSE
/// deltas are forwarded as they arrive. Chat Completions never sends the finished message, so the
/// trailing completed event is reassembled from those deltas rather than received.
///
/// ## Example
///
/// ```swift
/// let client = XAIClient(apiKey: "xai-...")
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .grok43
/// )
/// ```
public struct XAIClient: OpenAICompatibleClientProtocol {
    public typealias Model = GrokModel

    package let engine: OpenAICompatibleEngine

    /// Full chat-completions URL used when the caller does not supply one.
    ///
    /// The API contract has an empty base path, so this URL is sent verbatim. A replacement must
    /// be a complete completions URL rather than a host, and must not end in a slash — a trailing
    /// slash is what made the sibling Groq endpoint answer `Unknown request URL`.
    public static let defaultEndpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    /// Creates a client that authenticates with the given xAI API key.
    ///
    /// The key is sent as an `Authorization: Bearer` header. Retries are on by default (up to five
    /// after the first failure): retryable failures such as 429 and 5xx back off exponentially with
    /// jitter, except that a `Retry-After` or `x-ratelimit-reset-*` hint parsed from the response
    /// overrides the backoff curve. Retries cover `generate` and `executeAgentStep`; `chat` and
    /// `planToolCalls` are sent exactly once.
    ///
    /// - Parameters:
    ///   - apiKey: xAI API key.
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
            providerName: "xAI",
            session: session,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
