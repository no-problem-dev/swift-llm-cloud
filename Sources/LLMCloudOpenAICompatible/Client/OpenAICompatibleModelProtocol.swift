import LLMCloudClient
import LLMClient

/// OpenAI 互換プロバイダーのモデルプロトコル
public protocol OpenAICompatibleModelProtocol: Sendable, Equatable {
    /// モデル ID 文字列
    var id: String { get }

    /// LLMModel に変換
    func toLLMModel() -> LLMModel
}
