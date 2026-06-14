import Foundation
import LLMClient

extension MediaSource {
    /// `MediaSource` の 3 ケースを各プロバイダーの DTO へ畳み込む。
    ///
    /// ケース分岐（`.base64` / `.url` / `.fileReference`）はここに一元化し、
    /// 各プロバイダーは取り出した素材を自身のワイヤ形式へ詰めるクロージャだけを渡す。
    public func fold<T>(
        base64: (Data) -> T,
        url: (URL) -> T,
        fileReference: (String) -> T
    ) -> T {
        switch self {
        case .base64(let data):
            return base64(data)
        case .url(let value):
            return url(value)
        case .fileReference(let id):
            return fileReference(id)
        }
    }
}
