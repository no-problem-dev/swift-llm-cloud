import Foundation

/// OpenAI 互換 API レスポンスボディ
package struct OpenAICompatibleResponseBody: Decodable, Sendable {
    package let id: String
    package let object: String
    package let created: Int
    package let model: String
    package let choices: [OpenAICompatibleChoice]
    package let usage: OpenAICompatibleUsage
}

/// OpenAI 互換選択肢
package struct OpenAICompatibleChoice: Decodable, Sendable {
    package let index: Int
    package let message: OpenAICompatibleResponseMessage
    package let finishReason: String?
}

/// OpenAI 互換レスポンスメッセージ
package struct OpenAICompatibleResponseMessage: Decodable, Sendable {
    package let role: String
    package let content: String?
    package let toolCalls: [OpenAICompatibleResponseToolCall]?
}

/// OpenAI 互換レスポンス内ツール呼び出しの種別。
/// 未知の値は `nil` として扱い、前方互換性を保つ。
package enum OpenAICompatibleToolCallType: String {
    case function
}

/// OpenAI 互換レスポンス内ツール呼び出し
package struct OpenAICompatibleResponseToolCall: Decodable, Sendable {
    package let id: String
    package let type: String
    package let function: OpenAICompatibleResponseToolCallFunction
}

/// OpenAI 互換レスポンス内ツール呼び出し関数
package struct OpenAICompatibleResponseToolCallFunction: Decodable, Sendable {
    package let name: String
    package let arguments: String
}
