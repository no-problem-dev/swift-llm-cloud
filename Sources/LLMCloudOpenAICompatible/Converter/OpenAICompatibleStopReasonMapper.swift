import LLMClient

/// finishReason → LLMResponse.StopReason マッピング
package enum OpenAICompatibleStopReasonMapper {
    package static func map(_ reason: String?) -> LLMResponse.StopReason? {
        guard let reason = reason else { return nil }
        switch reason {
        case "stop":
            return .endTurn
        case "length":
            return .maxTokens
        case "tool_calls":
            return .toolUse
        default:
            return nil
        }
    }
}
