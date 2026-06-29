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

/// xAI Grok API クライアント。
///
/// Grok モデルを使用した構造化出力、チャット、
/// ツールコール、エージェント機能を提供する。
///
/// ## 使用例
///
/// ```swift
/// let client = XAIClient(apiKey: "xai-...")
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: .grok43
/// )
/// ```
public struct XAIClient: OpenAICompatibleClientProtocol {
    public typealias Model = GrokModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    /// API キーを指定して初期化
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
