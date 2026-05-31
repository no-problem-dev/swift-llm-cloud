import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient

/// Gemini API のレート制限ヘッダー抽出。挙動は ``RateLimitHeaderExtraction`` の
/// `.gemini` 設定（`retry-after` のみ）に集約。
public enum GeminiRateLimitExtractor: RateLimitInfoExtractable {
    public static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
        RateLimitHeaderExtraction.gemini.extract(from: response)
    }
}
