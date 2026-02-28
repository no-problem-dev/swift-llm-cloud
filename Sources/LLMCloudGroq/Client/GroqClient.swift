import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GroqModel + OpenAICompatibleModelProtocol

extension GroqModel: OpenAICompatibleModelProtocol {
    public func toLLMModel() -> LLMModel { .groq(self) }
}

// MARK: - GroqClient

/// Groq API クライアント
///
/// Groq のホステッドモデル（Llama, Qwen 等）を使用した構造化出力、チャット、
/// ツールコール、エージェント機能を提供します。
///
/// ## 使用例
///
/// ```swift
/// let client = GroqClient(apiKey: "gsk_...")
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: .llama3_3_70b
/// )
/// ```
public struct GroqClient: OpenAICompatibleClientProtocol {
    public typealias Model = GroqModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

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
            providerName: "Groq",
            session: session,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
