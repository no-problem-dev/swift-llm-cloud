import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAI Compatible API Group

/// OpenAI 互換 API のグループ定義
///
/// - Auth: `Authorization: Bearer` ヘッダー
/// - basePath は空文字列（エンドポイント URL に完全パスを含む）
/// - Custom Error Decoding: LLMError + RateLimitAwareError
enum OpenAICompatibleAPI: APIContractGroup {
    static let basePath: String = ""
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    // MARK: - Custom Error Decoding

    /// OpenAI 互換のエラーデコード
    ///
    /// ステータスコードに基づいて LLMError を生成し、
    /// レート制限ヘッダーから RateLimitInfo を抽出して RateLimitAwareError を構成する。
    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: any APIBodyDecoder    ) -> (any Error)? {
        let rateLimitInfo = extractRateLimitInfo(from: headers)
        let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)

        switch statusCode {
        case 401:
            return LLMError.unauthorized
        case 429:
            return RateLimitAwareError(
                underlyingError: .rateLimitExceeded,
                rateLimitInfo: rateLimitInfo,
                statusCode: 429
            )
        case 400:
            return LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            return LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            return RateLimitAwareError(
                underlyingError: .serverError(statusCode, errorResponse?.error.message ?? "Server error"),
                rateLimitInfo: rateLimitInfo,
                statusCode: statusCode
            )
        default:
            return LLMError.serverError(statusCode, "Unexpected status code")
        }
    }

    // MARK: - Rate Limit Extraction

    private static func extractRateLimitInfo(from headers: [String: String]) -> RateLimitInfo {
        func header(_ name: String) -> String? {
            headers[name] ?? headers[name.lowercased()]
        }

        let retryAfter = header("Retry-After")
            .flatMap { Double($0) }

        let remainingRequests = header("x-ratelimit-remaining-requests")
            .flatMap { Int($0) }

        let requestsResetIn = header("x-ratelimit-reset-requests")
            .flatMap { parseResetTime($0) }

        let remainingTokens = header("x-ratelimit-remaining-tokens")
            .flatMap { Int($0) }

        let tokensResetIn = header("x-ratelimit-reset-tokens")
            .flatMap { parseResetTime($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: remainingRequests,
            requestsResetIn: requestsResetIn,
            remainingTokens: remainingTokens,
            tokensResetIn: tokensResetIn
        )
    }

    private static func parseResetTime(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix("ms") {
            return Double(trimmed.dropLast(2)).map { $0 / 1000 }
        } else if trimmed.hasSuffix("s") {
            return Double(trimmed.dropLast(1))
        } else if trimmed.hasSuffix("m") {
            return Double(trimmed.dropLast(1)).map { $0 * 60 }
        } else if trimmed.hasSuffix("h") {
            return Double(trimmed.dropLast(1)).map { $0 * 3600 }
        }
        return Double(trimmed)
    }
}

// MARK: - Create Chat Completion Endpoint

extension OpenAICompatibleAPI {
    /// チャット補完エンドポイント（非ストリーミング）
    struct CreateChatCompletion: APIContract, APIInput {
        typealias Group = OpenAICompatibleAPI
        typealias Input = Self
        typealias Output = OpenAICompatibleResponseBody

        static let method: APIMethod = .post
        static let subPath: String = ""

        /// プロバイダー固有のカスタムヘッダー
        let customHeaders: [String: String]
        /// リクエストボディ
        let request: OpenAICompatibleRequestBody

        var pathParameters: [String: String] { [:] }
        var queryParameters: [String: String]? { nil }

        var additionalHeaders: [String: String] {
            customHeaders
        }

        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
            try encoder.encode(request)
        }

        static func decode(
            pathParameters: [String: String],
            queryParameters: [String: String],
            body: Data?,
            decoder: any APIBodyDecoder        ) throws -> Self {
            fatalError("Client-only contract")
        }
    }
}
