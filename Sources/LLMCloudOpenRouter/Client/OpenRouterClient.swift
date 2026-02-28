import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenRouterModel

/// OpenRouter モデル（任意のモデルIDを文字列で指定）
public struct OpenRouterModel: Sendable, Equatable, OpenAICompatibleModelProtocol {
    /// モデルID文字列
    public let id: String

    /// 初期化
    ///
    /// - Parameter id: OpenRouter のモデル ID（例: "anthropic/claude-sonnet-4", "openai/gpt-4o"）
    public init(_ id: String) {
        self.id = id
    }

    public func toLLMModel() -> LLMModel { .openRouter(id) }
}

// MARK: - OpenRouterClient

/// OpenRouter API クライアント
///
/// OpenRouter 経由で任意のモデルにアクセスするクライアントです。
/// 構造化出力、チャット、ツールコール、エージェント機能を提供します。
///
/// ## 使用例
///
/// ```swift
/// let client = OpenRouterClient(
///     apiKey: "sk-or-...",
///     appName: "MyApp",
///     siteUrl: "https://myapp.example.com"
/// )
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: OpenRouterModel("anthropic/claude-sonnet-4")
/// )
/// ```
public struct OpenRouterClient: OpenAICompatibleClientProtocol {
    public typealias Model = OpenRouterModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: OpenRouter API キー
    ///   - appName: アプリ名（X-Title ヘッダー、オプション）
    ///   - siteUrl: サイト URL（HTTP-Referer ヘッダー、オプション）
    ///   - endpoint: カスタムエンドポイント（オプション）
    ///   - session: カスタム URLSession（オプション）
    ///   - retryConfiguration: リトライ設定
    ///   - retryEventHandler: リトライイベントハンドラー
    public init(
        apiKey: String,
        appName: String? = nil,
        siteUrl: String? = nil,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        var customHeaders: [String: String] = [:]
        if let appName = appName {
            customHeaders["X-Title"] = appName
        }
        if let siteUrl = siteUrl {
            customHeaders["HTTP-Referer"] = siteUrl
        }

        self.engine = OpenAICompatibleEngine(
            apiKey: apiKey,
            endpoint: endpoint ?? Self.defaultEndpoint,
            providerName: "OpenRouter",
            session: session,
            customHeaders: customHeaders,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
