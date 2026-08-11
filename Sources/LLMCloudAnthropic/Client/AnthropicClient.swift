import LLMCloudClient
import LLMClient
import APIClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicClient

/// Type-safe client for the Anthropic Claude Messages API.
///
/// The model parameter is typed as `ClaudeModel`, so a model belonging to another provider
/// cannot be passed by mistake. Requests go to `POST /v1/messages`. Structured output is
/// requested through Anthropic's generally available `output_config.format` (constrained
/// decoding) rather than through prompt-only JSON coaxing.
///
/// Anthropic requires `max_tokens` on every request — unlike OpenAI, it has no server-side
/// default. When the caller passes `nil` this client sends 4096.
///
/// ## Example
///
/// ```swift
/// let client = AnthropicClient(apiKey: "sk-ant-...")
///
/// @Structured("User profile")
/// struct UserInfo {
///     @StructuredField("Display name")
///     var name: String
///     @StructuredField("Age in years", .minimum(0))
///     var age: Int
/// }
///
/// // The schema is derived from the return type.
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .sonnet
/// )
/// print(result.name)  // "Taro Yamada"
/// print(result.age)   // 35
///
/// // The same call, with token accounting attached.
/// let resultWithUsage: GenerationResult<UserInfo> = try await client.generateWithUsage(
///     input: "Taro Yamada is 35 years old.",
///     model: .sonnet
/// )
/// print("Input tokens: \(resultWithUsage.usage.inputTokens)")
/// print("Output tokens: \(resultWithUsage.usage.outputTokens)")
///
/// // Multimodal input.
/// let analysis: ImageAnalysis = try await client.generate(
///     input: LLMInput("Analyze this image", images: [imageContent]),
///     model: .sonnet
/// )
/// ```
///
/// ## Supported models
/// - `.opus` — alias for the current flagship Opus (Claude Opus 4.8)
/// - `.sonnet` — alias for the current Sonnet (Claude Sonnet 4.6), the balanced choice
/// - `.haiku` — alias for the current Haiku (Claude Haiku 4.5), fastest and cheapest
///
/// Version-pinned aliases (`.opus4_5`, `.sonnet4_5`, and so on) and explicitly dated versions
/// (`.opus4_1_version("...")`) are also accepted.
public struct AnthropicClient: StructuredLLMClient {
    public typealias Model = ClaudeModel

    public let provider: any LLMProvider

    let baseProvider: AnthropicProvider

    // MARK: - Package Access (for extension by other modules)

    package let apiKey: String

    /// Full URL of the messages endpoint this client was configured with, kept for inspection.
    ///
    /// Requests are not built from this value: the initializer hands the caller-supplied URL to
    /// the underlying provider as an API *base* URL, and the `/v1/messages` path is appended to
    /// it. Pass a host root such as `https://proxy.example.com`, not a full messages URL.
    package let endpoint: URL

    package let session: URLSession

    /// Retry behaviour wrapped around the provider.
    ///
    /// When enabled, retryable failures (429 and 5xx) are retried with exponential backoff, but
    /// the wait Anthropic advertises wins over the computed backoff: `retry-after` first, then
    /// `anthropic-ratelimit-requests-reset`, then `anthropic-ratelimit-tokens-reset`.
    public let retryConfiguration: RetryConfiguration

    /// Called once per retry, just before sleeping, with the attempt number and the delay.
    public let retryEventHandler: RetryEventHandler?

    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Initializers

    /// Creates a client for the given API key.
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API key, sent in the `x-api-key` header.
    ///   - endpoint: Base URL to send requests to; `/v1/messages` is appended to it. Defaults to
    ///     the public Anthropic API.
    ///   - session: Session backing the default transport.
    ///   - retryConfiguration: Retry behaviour. Enabled by default, and honours the
    ///     `anthropic-ratelimit-*` headers when deciding how long to wait.
    ///   - retryEventHandler: Observer invoked before each retry sleep.
    public init(
        apiKey: String,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, session: session,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint ?? Self.defaultEndpoint
        self.session = session
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler

        let baseProvider = AnthropicProvider(transport: transport, apiKey: apiKey, baseURL: endpoint)
        self.baseProvider = baseProvider

        if retryConfiguration.isEnabled {
            self.provider = RetryableProvider(
                provider: baseProvider,
                extractorType: AnthropicRateLimitExtractor.self,
                retryPolicy: retryConfiguration.policy,
                eventHandler: retryEventHandler
            )
        } else {
            self.provider = baseProvider
        }
    }

    // MARK: - StructuredLLMClient

    public func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: ClaudeModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await generateWithUsage(
            messages: [input.toLLMMessage()],
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        // Fold the schema description into the system prompt on top of output_config.format.
        let enhancedSystemPrompt = buildSystemPrompt(
            base: systemPrompt,
            schema: T.jsonSchema
        )

        let request = LLMRequest(
            model: .claude(model),
            messages: messages,
            systemPrompt: enhancedSystemPrompt,
            responseSchema: T.jsonSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let response = try await provider.send(request)
        return try decodeResponse(response, model: model.id)
    }

    // MARK: - Private Helpers

    /// Appends the schema's own description to the caller's system prompt.
    ///
    /// Only the description is restated in prose; the schema itself travels separately in
    /// `output_config.format`, where Anthropic enforces it by constrained decoding. The prefix
    /// added here is written in Japanese, so it shows up verbatim in the system prompt.
    private func buildSystemPrompt(base: String?, schema: JSONSchema) -> String {
        var parts: [String] = []

        if let base = base {
            parts.append(base)
        }

        if let description = schema.description {
            parts.append("出力形式: \(description)")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    /// Decodes the reply's leading text into the requested structured type.
    ///
    /// Only the first content block is read, so a reply whose leading block is a tool use rather
    /// than text fails with `LLMError.emptyResponse`. JSON keys are matched with
    /// `convertFromSnakeCase`, and a decode failure is wrapped in `LLMError.decodingFailed`.
    private func decodeResponse<T: StructuredProtocol>(_ response: LLMResponse, model: String) throws -> GenerationResult<T> {
        guard let text = response.content.first?.text else {
            throw LLMError.emptyResponse
        }

        guard let data = text.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let result = try decoder.decode(T.self, from: data)
            return GenerationResult(
                result: result,
                usage: response.usage,
                model: model,
                rawText: text,
                stopReason: response.stopReason
            )
        } catch {
            throw LLMError.decodingFailed(error)
        }
    }
}
