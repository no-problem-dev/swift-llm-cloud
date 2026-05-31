import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// OpenAI 互換 API のレート制限ヘッダー抽出。挙動は ``RateLimitHeaderExtraction`` の
/// `.openAICompatible` 設定（`x-ratelimit-*` + duration suffix reset）に集約。
package enum OpenAICompatibleRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.openAICompatible.extract(from: response)
    }
}
