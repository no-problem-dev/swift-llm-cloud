import LLMCloudClient
import LLMClient
import APIClient
import Foundation
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient

/// Client for Google's Gemini generative language API.
///
/// Structured generation sends the return type's JSON schema as Gemini's `responseSchema` and
/// decodes the reply back into that type. The model parameter is typed as `GeminiModel`, so a
/// model belonging to another provider cannot be passed by mistake.
///
/// ## Example
///
/// ```swift
/// let client = GeminiClient(apiKey: "...")
///
/// @Structured("User information")
/// struct UserInfo {
///     @StructuredField("Full name")
///     var name: String
///     @StructuredField("Age in years", .minimum(0))
///     var age: Int
/// }
///
/// // The schema is derived from the return type.
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .flash35
/// )
///
/// // Same call, with billed token counts attached.
/// let resultWithUsage: GenerationResult<UserInfo> = try await client.generateWithUsage(
///     input: "Taro Yamada is 35 years old.",
///     model: .flash35
/// )
/// print("Input tokens: \(resultWithUsage.usage.inputTokens)")
/// print("Output tokens: \(resultWithUsage.usage.outputTokens)")
///
/// // Multimodal input.
/// let analysis: ImageAnalysis = try await client.generate(
///     input: LLMInput("Describe this image", images: [imageContent]),
///     model: .flash35
/// )
/// ```
///
/// ## Models
///
/// `GeminiModel` carries both the current aliases (Gemini 3.x Flash, Flash-Lite, and Pro) and
/// version-pinned cases such as `.flash35_version("...")`. The Gemini 2.5 cases are retired for
/// new users and exist only so previously stored model ids still decode; filter on the model's
/// `isRetired` flag before offering one as a choice.
public struct GeminiClient: StructuredLLMClient {
    public typealias Model = GeminiModel

    public let provider: any LLMProvider

    let baseProvider: GeminiProvider

    /// Transport for the image endpoints, rooted at the models base URL.
    ///
    /// Serves Imagen `:predict` and Gemini image `:generateContent`, and authenticates with the
    /// `x-goog-api-key` header like the text endpoints do.
    package let mediaClient: APIClientImpl

    /// Transport for Veo video generation, rooted one path component above the models base URL.
    ///
    /// Veo returns a long-running operation whose status resource lives outside `models/`
    /// (`/v1beta/{operationName}`), so polling needs this shorter base URL.
    package let veoClient: APIClientImpl

    /// Lifecycle owner of the explicit prompt caches this client created.
    ///
    /// Gemini's `cachedContents` are server-side resources billed for storage, so they are owned
    /// per client instance (in practice, per session) and released by ``releasePromptCaches()``.
    let contextCache: GeminiContextCacheStore

    // MARK: - Package Access (for extension by other modules)

    package let apiKey: String

    package let baseURL: String

    package let session: URLSession

    public let retryConfiguration: RetryConfiguration

    public let retryEventHandler: RetryEventHandler?

    public static let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Initializers

    /// Creates a client that talks to the Gemini API with the given key.
    ///
    /// With retries enabled the non-streaming provider is wrapped in a retrying one. Gemini
    /// publishes no rate-limit budget headers, so backoff is driven by `retry-after` alone when
    /// the server sends it. Streaming calls are never retried.
    ///
    /// - Parameters:
    ///   - apiKey: Google AI API key, sent as the `x-goog-api-key` header.
    ///   - baseURL: Overrides the models base URL; the media and cache transports are derived
    ///     from it.
    ///   - session: URLSession used for the transport and for downloading generated video.
    ///   - retryConfiguration: Retry policy for non-streaming requests. Enabled by default.
    ///   - retryEventHandler: Observes each retry attempt.
    ///   - cacheEventHandler: Observes explicit prompt-cache lifecycle events such as creation,
    ///     reuse, and fallback to inline sending.
    public init(
        apiKey: String,
        baseURL: String? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil,
        cacheEventHandler: GeminiCacheEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, baseURL: baseURL, session: session,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler,
            cacheEventHandler: cacheEventHandler
        )
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        baseURL: String? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil,
        cacheEventHandler: GeminiCacheEventHandler? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler

        let baseProvider = GeminiProvider(transport: transport, apiKey: apiKey, baseURL: baseURL)
        self.baseProvider = baseProvider

        let mediaBaseURL = URL(string: baseURL ?? Self.defaultBaseURL)!
        self.mediaClient = APIClientImpl(
            baseURL: mediaBaseURL,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .default
        )
        self.veoClient = APIClientImpl(
            baseURL: mediaBaseURL.deletingLastPathComponentAsBase,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .default
        )
        // cachedContents sits outside models/ (/v1beta/cachedContents), so it needs the shorter
        // base URL. Auth is the x-goog-api-key header, same as generateContent.
        self.contextCache = GeminiContextCacheStore(
            apiClient: APIClientImpl(
                baseURL: mediaBaseURL.deletingLastPathComponentAsBase,
                transport: transport,
                authTokenProvider: StaticTokenProvider(token: apiKey),
                keyStyle: .default
            ),
            eventHandler: cacheEventHandler
        )

        if retryConfiguration.isEnabled {
            self.provider = RetryableProvider(
                provider: baseProvider,
                extractorType: GeminiRateLimitExtractor.self,
                retryPolicy: retryConfiguration.policy,
                eventHandler: retryEventHandler
            )
        } else {
            self.provider = baseProvider
        }
    }

    // MARK: - StructuredLLMClient

    /// Generates a structured value from one prompt.
    ///
    /// - Parameters:
    ///   - input: The prompt, optionally carrying images, audio, or video.
    ///   - model: Gemini model to serve the request.
    ///   - options: System prompt, temperature, and output ceiling.
    public func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: GeminiModel,
        options: GenerationOptions
    ) async throws -> GenerationResult<T> {
        try await generateWithUsage(
            messages: [input.toLLMMessage()],
            model: model,
            options: options
        )
    }

    /// Generates a structured value from a conversation history.
    ///
    /// - Parameters:
    ///   - messages: The conversation so far, oldest first.
    ///   - model: Gemini model to serve the request.
    ///   - options: System prompt, temperature, and output ceiling.
    public func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: GeminiModel,
        options: GenerationOptions
    ) async throws -> GenerationResult<T> {
        // Restate the schema description in the system prompt as well as sending responseSchema.
        let enhancedSystemPrompt = buildSystemPrompt(
            base: options.systemPrompt?.render(),
            schema: T.jsonSchema
        )

        let request = LLMRequest(
            model: .gemini(model),
            messages: messages,
            systemPrompt: enhancedSystemPrompt,
            responseSchema: T.jsonSchema,
            temperature: options.temperature,
            maxTokens: options.maxTokens
        )

        let response = try await provider.send(request)
        return try decodeResponse(response, model: model.id)
    }

    // MARK: - Private Helpers

    /// Joins the caller's system prompt with the schema description, blank line separated.
    ///
    /// Returns an empty string when there is neither a base prompt nor a schema description.
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

    /// Decodes the first text block of a response into the requested structured type.
    ///
    /// Gemini honours `responseSchema` but still wraps the JSON in a markdown fence often enough
    /// that the fence is stripped before decoding. Keys are matched with
    /// `convertFromSnakeCase`, and the surviving JSON text is kept on the result as `rawText`.
    ///
    /// - Throws: `LLMError.emptyResponse` when no text block came back, `LLMError.invalidEncoding`
    ///   when the text is not UTF-8, and `LLMError.decodingFailed` when it does not match the type.
    private func decodeResponse<T: StructuredProtocol>(_ response: LLMResponse, model: String) throws -> GenerationResult<T> {
        guard let text = response.content.first?.text else {
            throw LLMError.emptyResponse
        }

        // Unwrap the markdown code fence Gemini sometimes adds around JSON output.
        let jsonText = extractJSON(from: text)

        guard let data = jsonText.data(using: .utf8) else {
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
                rawText: jsonText,
                stopReason: response.stopReason
            )
        } catch {
            throw LLMError.decodingFailed(error)
        }
    }

    /// Strips a surrounding markdown code fence, if there is one.
    ///
    /// Handles both a `json`-tagged fence and an untagged one, matching the closing fence from
    /// the end so that fences inside the JSON do not truncate it. Text with no fence, or with an
    /// unterminated one, is returned trimmed and otherwise unchanged.
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```json") {
            let content = trimmed.dropFirst(7) // Drop the opening "```json".
            if let endIndex = content.range(of: "```", options: .backwards) {
                return String(content[content.startIndex..<endIndex.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Untagged fence, or one tagged with some other language.
        if trimmed.hasPrefix("```") {
            let content = trimmed.dropFirst(3) // Drop the opening "```".
            // Skip up to the first newline, which may hold a language tag.
            let afterLang: Substring
            if let newlineIndex = content.firstIndex(of: "\n") {
                afterLang = content[content.index(after: newlineIndex)...]
            } else {
                afterLang = content
            }
            if let endIndex = afterLang.range(of: "```", options: .backwards) {
                return String(afterLang[afterLang.startIndex..<endIndex.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // No fence to strip.
        return trimmed
    }

}
