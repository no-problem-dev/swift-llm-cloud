import Foundation

/// OpenAI 互換エラーレスポンス
package struct OpenAICompatibleErrorResponse: Decodable, Sendable {
    package let error: OpenAICompatibleError
}

/// OpenAI 互換エラー詳細
package struct OpenAICompatibleError: Decodable, Sendable {
    package let message: String
    package let type: String?
    package let param: String?
    package let code: String?
}
