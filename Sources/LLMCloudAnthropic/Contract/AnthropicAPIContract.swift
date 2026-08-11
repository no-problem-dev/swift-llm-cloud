import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Anthropic API Group

/// Contract group for the Anthropic Messages API.
///
/// - Auth: the API key travels in the `x-api-key` header, not as a bearer token.
/// - Common headers: `anthropic-version: 2023-06-01` on every request.
/// - Error decoding: HTTP failures become `LLMError`, and the rate-limited and server-error
///   cases are wrapped in `RateLimitAwareError` so the retry runner can read Anthropic's
///   advertised wait instead of guessing.
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

    /// Turns a failed Anthropic response into a typed error, carrying rate limit state along.
    ///
    /// The status code selects the `LLMError` case, and the response body supplies Anthropic's
    /// own message for 400 and 404. For 429 and 5xx the error is wrapped in a
    /// `RateLimitAwareError` holding the `retry-after` and `anthropic-ratelimit-*` values, which
    /// is what lets a retry wait exactly as long as Anthropic asked rather than backing off
    /// blindly. Every status code maps to some error, so the result is never `nil`.
    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: any APIBodyDecoder    ) -> (any Error)? {
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

    /// Reads Anthropic's rate limit headers off a failed response.
    ///
    /// Anthropic reports both a request budget and a token budget, under
    /// `anthropic-ratelimit-requests-*` and `anthropic-ratelimit-tokens-*`. The `-reset` headers
    /// are RFC 3339 absolute timestamps, not durations, so they are converted to seconds from
    /// now and clamped at zero. `Retry-After`, when present, is already a plain second count and
    /// takes precedence over both resets when a wait is chosen.
    private static func extractRateLimitInfo(from headers: [String: String]) -> RateLimitInfo {
        // Header lookup is case-insensitive: try the spelling as given, then all-lowercase.
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

    /// Converts an RFC 3339 reset timestamp into seconds remaining from now, never negative.
    ///
    /// Both the fractional-seconds and whole-second spellings are accepted; anything else
    /// yields `nil` so the caller falls back to another signal.
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
    /// Create-message endpoint, used for both single-shot replies and streams.
    ///
    /// It posts to `/v1/messages`, and the body decides which mode applies: setting `stream`
    /// makes Anthropic answer with an event stream, which the caller reads through the
    /// provider's event stream entry point instead of decoding ``AnthropicResponseBody``.
    struct CreateMessage: APIContract, APIInput {
        typealias Group = AnthropicAPI
        typealias Input = Self
        typealias Output = AnthropicResponseBody

        static let method: APIMethod = .post
        static let subPath: String = ""

        /// Opt-in beta feature names, joined with commas into the `anthropic-beta` header.
        ///
        /// Empty means the header is omitted entirely. Callers add values only when the request
        /// actually needs them, such as the Files API for `file_id` references or the extended
        /// cache TTL for one-hour prompt caching.
        let beta: [String]
        let request: AnthropicRequestBody

        init(beta: [String] = [], request: AnthropicRequestBody) {
            self.beta = beta
            self.request = request
        }

        var pathParameters: [String: String] { [:] }
        var queryParameters: [String: String]? { nil }

        var additionalHeaders: [String: String] {
            var headers: [String: String] = [:]
            if !beta.isEmpty {
                headers["anthropic-beta"] = beta.joined(separator: ",")
            }
            return headers
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

// MARK: - Anthropic Error Response Types

struct AnthropicErrorResponse: Decodable, Sendable {
    let type: String
    let error: AnthropicErrorDetail
}

struct AnthropicErrorDetail: Decodable, Sendable {
    let type: String
    let message: String
}
