import LLMClient

/// Maps the wire `finish_reason` onto the shared stop reason.
///
/// Only the three values every OpenAI-compatible vendor agrees on are recognized: `stop` becomes
/// end of turn, `length` becomes hitting the token cap, and `tool_calls` becomes a tool request.
/// Anything else — a missing field, or a vendor extension such as `content_filter` — maps to `nil`,
/// which reads downstream as "the vendor did not say", not as a normal completion.
package enum OpenAICompatibleStopReasonMapper {
    private enum FinishReason: String {
        case stop
        case length
        case toolCalls = "tool_calls"
    }

    package static func map(_ reason: String?) -> LLMResponse.StopReason? {
        switch reason.flatMap(FinishReason.init) {
        case .stop: return .endTurn
        case .length: return .maxTokens
        case .toolCalls: return .toolUse
        case nil: return nil
        }
    }
}
