import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Gemini API Group

/// Google Gemini API のグループ定義
///
/// - Auth: `x-goog-api-key` ヘッダー
/// - basePath は空文字列（baseURL にモデルベースパスを含む）
/// - Custom Error Decoding: LLMError + RateLimitAwareError
enum GeminiAPI: APIContractGroup {
    static let basePath: String = ""
    // Google 現行推奨は x-goog-api-key ヘッダー（query param の key は URL ログ漏洩リスクで非推奨）。
    static let auth: AuthScheme = .apiKey(headerName: "x-goog-api-key")
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    // MARK: - Custom Error Decoding

    /// Gemini 固有のエラーデコード
    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: any APIBodyDecoder    ) -> (any Error)? {
        let retryAfter = (headers["Retry-After"] ?? headers["retry-after"])
            .flatMap { Double($0) }

        let rateLimitInfo = RateLimitInfo(
            retryAfter: retryAfter,
            remainingRequests: nil,
            requestsResetIn: nil,
            remainingTokens: nil,
            tokensResetIn: nil
        )

        let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)

        // cachedContents 参照に固有のエラー（失効など）は専用型で返し、回復戦略に接続する
        if let message = errorResponse?.error.message,
           let cacheError = GeminiCacheErrorClassifier.classify(statusCode: statusCode, message: message) {
            return cacheError
        }

        switch statusCode {
        case 401, 403:
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
}

// MARK: - Generate Content Endpoint

extension GeminiAPI {
    /// コンテンツ生成エンドポイント（非ストリーミング）
    ///
    /// URL: `{baseURL}/{modelId}:generateContent?key={apiKey}`
    struct GenerateContent: APIContract, APIInput {
        typealias Group = GeminiAPI
        typealias Input = Self
        typealias Output = GeminiResponseBody

        static let method: APIMethod = .post
        static let subPath: String = "/:modelId:generateContent"

        /// モデル ID
        let modelId: String
        /// リクエストボディ
        let request: GeminiRequestBody

        var pathParameters: [String: String] {
            ["modelId": modelId]
        }

        var queryParameters: [String: String]? { nil }

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

    /// ストリーミング生成エンドポイント。
    ///
    /// URL: `{baseURL}/{modelId}:streamGenerateContent?key={apiKey}&alt=sse`
    struct StreamGenerateContent: APIContract, APIInput {
        typealias Group = GeminiAPI
        typealias Input = Self
        typealias Output = GeminiResponseBody

        static let method: APIMethod = .post
        static let subPath: String = "/:modelId:streamGenerateContent"

        let modelId: String
        let request: GeminiRequestBody

        var pathParameters: [String: String] { ["modelId": modelId] }
        var queryParameters: [String: String]? { ["alt": "sse"] }

        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
            try encoder.encode(request)
        }

        static func decode(
            pathParameters: [String: String],
            queryParameters: [String: String],
            body: Data?,
            decoder: any APIBodyDecoder
        ) throws -> Self {
            fatalError("Client-only contract")
        }
    }
}
