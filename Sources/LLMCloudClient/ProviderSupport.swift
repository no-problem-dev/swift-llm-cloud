import APIClient
import Foundation
import LLMClient

/// API キーをそのまま返す ``AuthTokenProvider``。各プロバイダ共通。
package struct StaticTokenProvider: AuthTokenProvider {
    package let token: String
    package init(token: String) { self.token = token }
    package func getToken() async throws -> String? { token }
}

/// ベースのシステムプロンプトと制約プロンプトを合成する。各プロバイダ共通。
package func composeSystemPrompt(base: String?, constraints: SystemPrompt?) -> String? {
    switch (base, constraints) {
    case (let base?, let constraints?): return "\(base)\n\n\(constraints.render())"
    case (let base?, nil): return base
    case (nil, let constraints?): return constraints.render()
    case (nil, nil): return nil
    }
}

/// 通信層の ``APIError`` をドメインの ``LLMError`` へ写像する。各プロバイダ共通。
package func mapAPIErrorToLLMError(_ error: APIError) -> LLMError {
    switch error {
    case .unauthorized: return .unauthorized
    case .networkError(let underlying): return .networkError(underlying)
    case .decodingError(let underlying): return .decodingFailed(underlying)
    case .invalidURL, .invalidResponse: return .invalidRequest("Invalid URL or response")
    case .httpError(let statusCode, _): return .serverError(statusCode, "HTTP error")
    }
}
