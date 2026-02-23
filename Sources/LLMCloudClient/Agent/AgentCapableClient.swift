import Foundation
import LLMClient
import LLMTool

// MARK: - AgentCapableClient Protocol

/// エージェントループをサポートするクライアントのプロトコル
///
/// `ToolCallableClient` を拡張し、エージェントループの実装に必要な
/// メソッドを提供します。各プロバイダーはこのプロトコルに適合することで
/// エージェント機能を利用可能にします。
public protocol AgentCapableClient: ToolCallableClient {
    /// エージェントステップを実行
    ///
    /// メッセージ履歴、ツール、オプションの構造化出力スキーマを含むリクエストを送信します。
    ///
    /// - Parameters:
    ///   - messages: メッセージ履歴
    ///   - model: 使用するモデル
    ///   - systemPrompt: システムプロンプト
    ///   - tools: 使用可能なツール
    ///   - toolChoice: ツール選択設定
    ///   - responseSchema: 期待する出力スキーマ（最終出力用）
    /// - Returns: LLM レスポンス
    func executeAgentStep(
        messages: [LLMMessage],
        model: Model,
        systemPrompt: Prompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?
    ) async throws -> LLMResponse
}
