import Foundation

/// Which field name a vendor wants the output token cap under.
///
/// Being OpenAI-compatible is a promise about the shape of requests and responses, not about the
/// exact set of fields, and the token cap is where that promise runs out. OpenAI, Groq, and xAI
/// have deprecated `max_tokens` in favour of `max_completion_tokens`. Mistral, DeepSeek, and
/// OpenRouter accept only `max_tokens` — sending `max_completion_tokens` to Mistral is rejected
/// outright with `422 Extra inputs are not permitted`, so this cannot be papered over by sending
/// both. Each vendor's client picks its case at construction and the request body encodes the cap
/// under whichever name is chosen.
public enum OpenAICompatibleMaxTokensParameter: String, Sendable {
    /// Wanted by OpenAI, Groq, and xAI. This is the default for clients that do not say otherwise.
    case maxCompletionTokens = "max_completion_tokens"
    /// Required by Mistral, DeepSeek, and OpenRouter.
    case maxTokens = "max_tokens"
}
