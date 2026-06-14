import Foundation

/// OpenAI 互換 API における最大生成トークン数の指定フィールド名。
///
/// 「OpenAI 互換」はリクエスト/レスポンスの形の契約であって、フィールド集合まで
/// 完全一致するわけではない。最大トークン指定は実プロバイダーで分岐する:
///
/// - `max_completion_tokens`: OpenAI / Groq / xAI(Grok-4 reasoning)。
///   これらは `max_tokens` を deprecated 扱いにしている。
/// - `max_tokens`: Mistral / DeepSeek / OpenRouter。Mistral は `max_completion_tokens`
///   を送ると `422 Extra inputs are not permitted` を返す。
///
/// プロバイダーごとにどちらを送るかを明示するための型。
public enum OpenAICompatibleMaxTokensParameter: String, Sendable {
    /// `max_completion_tokens`（OpenAI / Groq / xAI）
    case maxCompletionTokens = "max_completion_tokens"
    /// `max_tokens`（Mistral / DeepSeek / OpenRouter）
    case maxTokens = "max_tokens"
}
