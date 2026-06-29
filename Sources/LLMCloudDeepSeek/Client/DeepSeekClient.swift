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

/// DeepSeek API クライアント。
///
/// DeepSeek-V4 モデル（`.v4Flash` / `.v4Pro`）を使用した構造化出力、チャット、
/// ツールコール、エージェント機能を提供する。
///
/// ## 使用例
///
/// ```swift
/// let client = DeepSeekClient(apiKey: "sk-...")
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: .v4Flash
/// )
/// ```
public struct DeepSeekClient: OpenAICompatibleClientProtocol {
    public typealias Model = DeepSeekModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!

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
            providerName: "DeepSeek",
            session: session,
            // DeepSeek は max_tokens を使う（max_completion_tokens 非対応）。
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
