import LLMClient

/// finishReason → LLMResponse.StopReason マッピング
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
