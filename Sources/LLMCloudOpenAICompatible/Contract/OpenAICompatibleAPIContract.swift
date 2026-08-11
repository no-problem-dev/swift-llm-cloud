import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAI Compatible API Group

/// Contract group for vendors exposing an OpenAI-shaped chat-completions endpoint.
///
/// The base path is deliberately empty: every vendor is configured with its complete endpoint URL,
/// path included, so nothing is appended to it. Auth is `Authorization: Bearer`. Error decoding is
/// overridden here rather than left to the generic client, so that a 429 or a 5xx reaches the retry
/// layer with the vendor's rate-limit headers still attached.
enum OpenAICompatibleAPI: APIContractGroup {
    static let basePath: String = ""
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    // MARK: - Custom Error Decoding

    /// Turns a failed response into a typed error, keeping rate-limit state attached to it.
    ///
    /// The status code alone decides the case, so a body that fails to parse never blocks the
    /// mapping. 401 becomes `LLMError.unauthorized`; 400 and 404 become `invalidRequest` and
    /// `modelNotFound`, quoting the vendor's own `error.message` when it is there. 429 and 5xx
    /// become `RateLimitAwareError` carrying the parsed headers, which is what lets the retry layer
    /// wait for the reported reset instead of guessing. Every other status becomes a generic server
    /// error, and the vendor's message is dropped with it.
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

    /// Reads rate-limit state out of the response headers of a failed request.
    ///
    /// Each name is tried as written and then lowercased, because vendors disagree on header case.
    /// `Retry-After` is read as a number of seconds only — the HTTP-date form of that header is
    /// treated as absent. Reset values carry a unit suffix (`ms`, `s`, `m`, `h`), and a bare number
    /// is taken as seconds.
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
    /// The chat-completions call, non-streaming: one request, one complete response body.
    struct CreateChatCompletion: APIContract, APIInput {
        typealias Group = OpenAICompatibleAPI
        typealias Input = Self
        typealias Output = OpenAICompatibleResponseBody

        static let method: APIMethod = .post
        static let subPath: String = ""

        let customHeaders: [String: String]
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
