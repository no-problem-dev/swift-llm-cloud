import Foundation

/// `/v1/responses` の SSE ストリーミングイベント。
///
/// ワイヤの実態（公式 SDK のパーサと同じ扱い）:
/// - `event:` 行には依存しない。`data:` の JSON をデコードし、中の `type` で分岐する
/// - 正規の終端は `response.completed` / `response.failed` / `response.incomplete`。
///   `[DONE]` センチネルには依存しない（届いたら無視する）
/// - デルタは表示用で、ground truth は `response.completed` に入る完全な Response
///   オブジェクト（output 配列 / usage / status）
///
/// 消費に必要なイベントだけを解釈し、残り（`output_item.added` /
/// `content_part.added` / `function_call_arguments.delta` 等）は `.ignored` に落とす。
/// ツール引数のデルタも `.completed` の確定値から取るため個別解釈しない。
package enum OpenAIResponsesStreamEvent {
    /// `response.output_text.delta`
    case outputTextDelta(String)
    /// `response.reasoning_summary_text.delta` / `response.reasoning_text.delta`
    case reasoningTextDelta(String)
    /// `response.completed`（完全な Response 同梱）
    case completed(OpenAIResponsesResponseBody)
    /// `response.failed` / `response.incomplete` / `error`
    case failed(message: String)
    /// 解釈対象外のイベント・`[DONE]` センチネル
    case ignored

    package init(data: String) {
        guard data != "[DONE]" else {
            self = .ignored
            return
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8)) else {
            self = .ignored
            return
        }
        switch payload.type {
        case "response.output_text.delta":
            self = payload.delta.map { .outputTextDelta($0) } ?? .ignored
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            self = payload.delta.map { .reasoningTextDelta($0) } ?? .ignored
        case "response.completed":
            self = payload.response.map { .completed($0.body) } ?? .ignored
        case "response.failed":
            self = .failed(message: payload.response?.errorMessage ?? "Response failed")
        case "response.incomplete":
            self = .failed(message: payload.response?.incompleteReason.map { "Response incomplete: \($0)" }
                ?? "Response incomplete")
        case "error":
            self = .failed(message: payload.message ?? "Unknown streaming error")
        default:
            self = .ignored
        }
    }

    /// `data:` の JSON。イベント種別ごとに使うフィールドが違うため全て optional で受ける。
    private struct Payload: Decodable {
        let type: String
        let delta: String?
        let message: String?
        let response: ResponseEnvelope?
    }

    /// ライフサイクルイベントの `response` フィールド。完了時は完全な Response として、
    /// 失敗時はエラー情報の運搬体として読む。
    package struct ResponseEnvelope: Decodable {
        package let body: OpenAIResponsesResponseBody
        package let errorMessage: String?
        package let incompleteReason: String?

        private enum CodingKeys: String, CodingKey {
            case error
            case incompleteDetails = "incomplete_details"
        }

        private struct ErrorInfo: Decodable {
            let message: String?
        }

        private struct IncompleteDetails: Decodable {
            let reason: String?
        }

        package init(from decoder: Decoder) throws {
            body = try OpenAIResponsesResponseBody(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            errorMessage = (try? container.decodeIfPresent(ErrorInfo.self, forKey: .error))??.message
            incompleteReason = (try? container.decodeIfPresent(IncompleteDetails.self, forKey: .incompleteDetails))??.reason
        }
    }
}
