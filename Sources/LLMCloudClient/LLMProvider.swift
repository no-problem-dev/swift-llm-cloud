import Foundation
import LLMClient

// MARK: - LLMProvider Protocol

/// LLM プロバイダーの共通インターフェース
///
/// このプロトコルは内部実装で使用されます。
/// 外部からは `StructuredLLMClient` プロトコルを使用してください。
public protocol LLMProvider: Sendable {
    /// リクエストを送信してレスポンスを取得
    ///
    /// - Parameter request: LLM リクエスト
    /// - Returns: LLM レスポンス
    /// - Throws: `LLMError` - 通信エラー、認証エラーなど
    func send(_ request: LLMRequest) async throws -> LLMResponse
}

// MARK: - LLMRequest

/// LLM への統一リクエスト形式
///
/// 基本的な LLM リクエストのみを扱います。
/// ツールコール機能は LLMTool モジュールで拡張されます。
public struct LLMRequest: Sendable {
    /// 使用するモデル
    public let model: LLMModel

    /// メッセージ履歴
    public let messages: [LLMMessage]

    /// システムプロンプト（オプション）
    public let systemPrompt: String?

    /// 構造化出力のスキーマ（nil の場合はプレーンテキスト）
    public let responseSchema: JSONSchema?

    /// 温度パラメータ（0.0-1.0）
    public let temperature: Double?

    /// 最大トークン数
    public let maxTokens: Int?

    /// リクエストを初期化
    public init(
        model: LLMModel,
        messages: [LLMMessage],
        systemPrompt: String? = nil,
        responseSchema: JSONSchema? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.responseSchema = responseSchema
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

// MARK: - LLMModel

/// LLM モデル指定
public enum LLMModel: Sendable, Equatable {
    /// Anthropic Claude モデル
    case claude(ClaudeModel)

    /// OpenAI GPT モデル
    case gpt(GPTModel)

    /// Google Gemini モデル
    case gemini(GeminiModel)

    /// カスタムモデル ID
    case custom(String)

    /// モデル ID 文字列を取得
    public var id: String {
        switch self {
        case .claude(let model):
            return model.id
        case .gpt(let model):
            return model.id
        case .gemini(let model):
            return model.id
        case .custom(let id):
            return id
        }
    }
}
