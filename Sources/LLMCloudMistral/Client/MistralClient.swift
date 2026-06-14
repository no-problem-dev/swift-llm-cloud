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

/// Mistral AI API クライアント
///
/// Mistral モデルを使用した構造化出力、チャット、
/// ツールコール、エージェント機能を提供します。
///
/// ## 使用例
///
/// ```swift
/// let client = MistralClient(apiKey: "...")
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: .large
/// )
/// ```
public struct MistralClient: OpenAICompatibleClientProtocol {
    public typealias Model = MistralModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!

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
            providerName: "Mistral",
            session: session,
            // Mistral は max_completion_tokens を 422 で拒否する（max_tokens のみ）。
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
