import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Anthropic API Group

/// Anthropic Messages API のグループ定義
///
/// - Auth: `x-api-key` ヘッダー
/// - Common Headers: `anthropic-version: 2023-06-01`
/// - Custom Error Decoding: LLMError + RateLimitAwareError
enum AnthropicAPI: APIContractGroup {
    static let basePath: String = "/v1/messages"
    static let auth: AuthScheme = .apiKey(headerName: "x-api-key")
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = ["anthropic-version": "2023-06-01"]

    private nonisolated(unsafe) static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Custom Error Decoding

    /// Anthropic 固有のエラーデコード
    ///
    /// ステータスコードに基づいて LLMError を生成し、
    /// レート制限ヘッダーから RateLimitInfo を抽出して RateLimitAwareError を構成する。
    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: JSONDecoder
    ) -> (any Error)? {
        let rateLimitInfo = extractRateLimitInfo(from: headers)
        let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)

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
        // ヘッダーキーは case-insensitive で取得
        func header(_ name: String) -> String? {
            headers[name] ?? headers[name.lowercased()]
        }

        let retryAfter = header("Retry-After").flatMap { Double($0) }

        let remainingRequests = header("anthropic-ratelimit-requests-remaining")
            .flatMap { Int($0) }

        let requestsResetIn = header("anthropic-ratelimit-requests-reset")
            .flatMap { parseRFC3339ToInterval($0) }

        let remainingTokens = header("anthropic-ratelimit-tokens-remaining")
            .flatMap { Int($0) }

        let tokensResetIn = header("anthropic-ratelimit-tokens-reset")
            .flatMap { parseRFC3339ToInterval($0) }

        return RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: remainingRequests,
            requestsResetIn: requestsResetIn,
            remainingTokens: remainingTokens,
            tokensResetIn: tokensResetIn
        )
    }

    private static func parseRFC3339ToInterval(_ value: String) -> TimeInterval? {
        if let date = isoFractionalFormatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        if let date = isoFormatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}

// MARK: - Create Message Endpoint

extension AnthropicAPI {
    /// メッセージ作成エンドポイント（非ストリーミング）
    struct CreateMessage: APIContract, APIInput {
        typealias Group = AnthropicAPI
        typealias Input = Self
        typealias Output = AnthropicResponseBody

        static let method: APIMethod = .post
        static let subPath: String = ""

        /// 構造化出力用ベータヘッダー
        let beta: String?
        /// リクエストボディ
        let request: AnthropicRequestBody

        var pathParameters: [String: String] { [:] }
        var queryParameters: [String: String]? { nil }

        var additionalHeaders: [String: String] {
            var headers: [String: String] = [:]
            if let beta {
                headers["anthropic-beta"] = beta
            }
            return headers
        }

        func encodeBody(using encoder: JSONEncoder) throws -> Data? {
            try encoder.encode(request)
        }

        static func decode(
            pathParameters: [String: String],
            queryParameters: [String: String],
            body: Data?,
            decoder: JSONDecoder
        ) throws -> Self {
            fatalError("Client-only contract")
        }
    }
}

// MARK: - Anthropic Error Response Types

struct AnthropicErrorResponse: Decodable, Sendable {
    let type: String
    let error: AnthropicErrorDetail
}

struct AnthropicErrorDetail: Decodable, Sendable {
    let type: String
    let message: String
}
