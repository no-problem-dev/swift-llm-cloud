import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// Anthropic API のレート制限ヘッダー抽出。挙動は ``RateLimitHeaderExtraction`` の
/// `.anthropic` 設定（`anthropic-ratelimit-*` + RFC3339 reset）に集約。
enum AnthropicRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.anthropic.extract(from: response)
    }
}
