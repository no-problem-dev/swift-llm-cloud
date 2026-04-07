import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
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

    /// API キー
    public var apiKey: String { engine.apiKey }

    /// エンドポイント
    public var endpoint: URL { engine.endpoint }

    /// URLSession
    public var session: URLSession { engine.session }

    /// 組織 ID
    public let organization: String?

    /// リトライ設定
    public var retryConfiguration: RetryConfiguration { engine.retryConfiguration }

    /// リトライイベントハンドラー
    public var retryEventHandler: RetryEventHandler? { engine.retryEventHandler }

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Initializers

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API キー
    ///   - organization: 組織 ID（オプション）
    ///   - endpoint: カスタムエンドポイント（オプション）
    ///   - session: カスタム URLSession（オプション）
    ///   - retryConfiguration: リトライ設定（デフォルト: 有効）
    ///   - retryEventHandler: リトライイベントハンドラー（オプション）
    public init(
        apiKey: String,
        organization: String? = nil,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.organization = organization

        var customHeaders: [String: String] = [:]
        if let org = organization {
            customHeaders["OpenAI-Organization"] = org
        }

        self.engine = OpenAICompatibleEngine(
            apiKey: apiKey,
            endpoint: endpoint ?? Self.defaultEndpoint,
            providerName: "OpenAI",
            session: session,
            customHeaders: customHeaders,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
