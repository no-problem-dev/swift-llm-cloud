import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Gemini API Group

/// Contract group for the Gemini text generation endpoints.
///
/// Authentication is the `x-goog-api-key` header. The base path is empty because the models path
/// is already part of the base URL. Error decoding is custom: cache failures become
/// ``GeminiCachedContentError``, throttling and server errors are wrapped so the retry layer can
/// see the response, and everything else maps to the shared error type.
enum GeminiAPI: APIContractGroup {
    static let basePath: String = ""
    // Google now recommends the x-goog-api-key header; passing the key as a query parameter risks
    // leaking it into URL logs.
    static let auth: AuthScheme = .apiKey(headerName: "x-goog-api-key")
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    // MARK: - Custom Error Decoding

    /// Turns a Gemini error response into the most specific error type available.
    ///
    /// A 429 or 5xx is wrapped in a rate-limit-aware error carrying `retry-after` when the server
    /// sent it, which is the only budget signal Gemini publishes. Cache-specific failures are
    /// classified from the message text first, because their status codes are indistinguishable
    /// from ordinary bad requests and missing resources.
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

        // Cache-specific failures (an expired resource, for one) get their own type so the
        // caller's recovery can act on them.
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
    /// `POST {baseURL}/{modelId}:generateContent` — one complete, non-streaming generation.
    struct GenerateContent: APIContract, APIInput {
        typealias Group = GeminiAPI
        typealias Input = Self
        typealias Output = GeminiResponseBody

        static let method: APIMethod = .post
        static let subPath: String = "/:modelId:generateContent"

        let modelId: String
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

    /// `POST {baseURL}/{modelId}:streamGenerateContent` — the same generation as server-sent events.
    ///
    /// The `alt=sse` query parameter is what selects SSE framing; without it Gemini streams a
    /// JSON array instead. Each event's payload is a whole response body, not a delta.
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
