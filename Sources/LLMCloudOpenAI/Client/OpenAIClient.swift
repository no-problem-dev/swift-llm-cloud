import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import APIClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GPTModel + OpenAICompatibleModelProtocol

extension GPTModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .gpt(self) }
}

// MARK: - OpenAIClient

/// OpenAI GPT API クライアント
///
/// GPT モデルを使用して型安全な構造化出力を生成します。
/// モデル選択は `GPTModel` 型に制約されており、
/// 他のプロバイダーのモデルを誤って指定することはできません。
///
/// ## 使用例
///
/// ```swift
/// let client = OpenAIClient(apiKey: "sk-...")
///
/// @Structured("ユーザー情報")
/// struct UserInfo {
///     @StructuredField("ユーザー名")
///     var name: String
///     @StructuredField("年齢", .minimum(0))
///     var age: Int
/// }
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: .gpt4o
/// )
/// ```
public struct OpenAIClient: OpenAICompatibleClientProtocol {
    public typealias Model = GPTModel

    package let engine: OpenAICompatibleEngine

    /// Responses API (`/v1/responses`) 専用エンジン。
    /// reasoning モデル + function tools の組み合わせは Chat Completions では拒否されるため、
    /// `executeAgentStep` 内で必要に応じてこちらに routing する。
    package let responsesEngine: OpenAIResponsesEngine

    /// メディア系エンドポイント(`/v1/audio`, `/v1/images`, `/v1/videos`)用の APIClient。
    package let mediaClient: APIClientImpl

    /// API キー
    package var apiKey: String { engine.apiKey }

    /// エンドポイント
    package var endpoint: URL { engine.endpoint }

    /// URLSession
    package var session: URLSession { engine.session }

    /// 組織 ID
    public let organization: String?

    /// リトライ設定
    public var retryConfiguration: RetryConfiguration { engine.retryConfiguration }

    /// リトライイベントハンドラー
    public var retryEventHandler: RetryEventHandler? { engine.retryEventHandler }

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Responses API のデフォルトエンドポイント
    public static let defaultResponsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    // MARK: - Initializers

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API キー
    ///   - organization: 組織 ID（オプション）
    ///   - endpoint: Chat Completions のカスタムエンドポイント（オプション）
    ///   - responsesEndpoint: Responses API のカスタムエンドポイント（オプション）
    ///   - session: カスタム URLSession（オプション）
    ///   - retryConfiguration: リトライ設定（デフォルト: 有効）
    ///   - retryEventHandler: リトライイベントハンドラー（オプション）
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

        // `/v1/chat/completions` → `/v1` をメディアの baseURL とする。
        self.mediaClient = APIClientImpl(
            baseURL: chatEndpoint.deletingLastPathComponent().deletingLastPathComponent(),
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            defaultHeaders: customHeaders,
            keyStyle: .snakeCase
        )
    }
}
