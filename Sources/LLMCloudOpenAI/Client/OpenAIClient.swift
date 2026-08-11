import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import LLMAgentStep
import APIClient
import Foundation
import HTTPTransport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GPTModel + OpenAICompatibleModelProtocol

extension GPTModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .gpt(self) }
}

// MARK: - OpenAIClient

/// Client for the OpenAI API that produces type-safe structured output from GPT models.
///
/// The model parameter is constrained to `GPTModel`, so a model belonging to another provider
/// cannot be passed by mistake. Calls go to Chat Completions by default; agent steps that combine
/// a reasoning model with function tools, and every streaming call, are routed to the Responses
/// API (`/v1/responses`) instead, because Chat Completions rejects that combination.
///
/// ## Example
///
/// ```swift
/// let client = OpenAIClient(apiKey: "sk-...")
///
/// @Structured("User information")
/// struct UserInfo {
///     @StructuredField("User name")
///     var name: String
///     @StructuredField("Age", .minimum(0))
///     var age: Int
/// }
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: .gpt4o
/// )
/// ```
public struct OpenAIClient: OpenAICompatibleClientProtocol {
    public typealias Model = GPTModel

    package let engine: OpenAICompatibleEngine

    /// Engine dedicated to the Responses API.
    ///
    /// Chat Completions rejects a reasoning model as soon as function tools are attached, so
    /// `executeAgentStep` routes that combination here. Streaming always uses this engine.
    package let responsesEngine: OpenAIResponsesEngine

    /// API client for the audio, image, and video endpoints.
    ///
    /// Its base URL is the chat endpoint with the last two path components stripped, so it lands
    /// on `/v1` and a custom `endpoint` keeps media calls on the same host. Unlike the two chat
    /// engines it uses snake-case key conversion, because the media bodies declare no coding keys.
    package let mediaClient: APIClientImpl

    package var apiKey: String { engine.apiKey }

    package var endpoint: URL { engine.endpoint }

    package var session: URLSession { engine.session }

    /// Organization the requests are attributed to.
    ///
    /// When non-nil it is sent as the `OpenAI-Organization` header on every request made by the
    /// chat engine, the Responses engine, and the media client.
    public let organization: String?

    public var retryConfiguration: RetryConfiguration { engine.retryConfiguration }

    public var retryEventHandler: RetryEventHandler? { engine.retryEventHandler }

    /// Chat Completions URL used when no custom endpoint is supplied.
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Responses API URL used when no custom endpoint is supplied.
    public static let defaultResponsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    // MARK: - Initializers

    /// Creates a client that authenticates with the given API key.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key, sent as a bearer token on every request.
    ///   - organization: Organization ID for the `OpenAI-Organization` header.
    ///   - endpoint: Overrides the Chat Completions URL. The media base URL is derived from it,
    ///     so pointing this at a proxy moves audio, image, and video calls there as well.
    ///   - responsesEndpoint: Overrides the Responses API URL. It is independent of `endpoint`;
    ///     a proxy that serves both has to be passed twice.
    ///   - session: Session backing the default transport.
    ///   - retryConfiguration: Retry policy shared by the chat and Responses engines. Media calls
    ///     are not retried.
    ///   - retryEventHandler: Called before each retry sleep with the attempt and the delay.
    public init(
        apiKey: String,
        organization: String? = nil,
        endpoint: URL? = nil,
        responsesEndpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, organization: organization, endpoint: endpoint,
            responsesEndpoint: responsesEndpoint, session: session,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        organization: String? = nil,
        endpoint: URL? = nil,
        responsesEndpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.organization = organization

        var customHeaders: [String: String] = [:]
        if let org = organization {
            customHeaders["OpenAI-Organization"] = org
        }

        let chatEndpoint = endpoint ?? Self.defaultEndpoint
        self.engine = OpenAICompatibleEngine(
            transport: transport,
            apiKey: apiKey,
            endpoint: chatEndpoint,
            providerName: "OpenAI",
            session: session,
            customHeaders: customHeaders,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )

        self.responsesEngine = OpenAIResponsesEngine(
            transport: transport,
            apiKey: apiKey,
            endpoint: responsesEndpoint ?? Self.defaultResponsesEndpoint,
            customHeaders: customHeaders,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )

        // Media calls hang off `/v1`, which is the chat endpoint minus `chat/completions`.
        self.mediaClient = APIClientImpl(
            baseURL: chatEndpoint.deletingLastPathComponentAsBase.deletingLastPathComponentAsBase,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            defaultHeaders: customHeaders,
            keyStyle: .snakeCase
        )
    }
}
