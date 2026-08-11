import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAI Responses API Group

/// Contract group for the OpenAI Responses API.
///
/// - Auth: `Authorization: Bearer`.
/// - The base path is empty, because the endpoint URL already carries the full path.
/// - Key conversion must stay off. Both the request and the response types spell out their own
///   coding keys, so snake-case conversion would rewrite keys that are already correct.
/// - Errors are decoded here rather than surfacing as HTTP failures: 429 and 5xx are wrapped in
///   ``RateLimitAwareError`` carrying the retry hints read from the `retry-after` and
///   `x-ratelimit-*` headers, so the retry runner can wait as long as OpenAI asked.
enum OpenAIResponsesAPI: APIContractGroup {
    static let basePath: String = ""
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: any APIBodyDecoder
    ) -> (any Error)? {
        let rateLimitInfo = RateLimitHeaderExtraction.openAICompatible.extract(from: headers)
        let message = (try? JSONDecoder().decode(OpenAIResponsesErrorBody.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8)
            ?? "Unknown error"

        switch statusCode {
        case 401:
            return LLMError.unauthorized
        case 429:
            return RateLimitAwareError(underlyingError: .rateLimitExceeded, rateLimitInfo: rateLimitInfo, statusCode: 429)
        case 400:
            return LLMError.invalidRequest(message)
        case 404:
            return LLMError.modelNotFound(message)
        case 500...599:
            return RateLimitAwareError(
                underlyingError: .serverError(statusCode, message), rateLimitInfo: rateLimitInfo, statusCode: statusCode
            )
        default:
            return LLMError.serverError(statusCode, message)
        }
    }
}

// MARK: - Create Response Endpoint

extension OpenAIResponsesAPI {
    /// `POST /v1/responses` — creates a response.
    ///
    /// The same contract serves both paths: the body decides which one runs. With `stream` unset
    /// the client decodes a single response body; with `stream` true the client reads the reply
    /// as an SSE event stream instead.
    struct CreateResponse: APIContract, APIInput {
        typealias Group = OpenAIResponsesAPI
        typealias Input = Self
        typealias Output = OpenAIResponsesResponseBody

        static let method: APIMethod = .post
        static let subPath: String = ""

        let customHeaders: [String: String]
        let request: OpenAIResponsesRequestBody

        var pathParameters: [String: String] { [:] }
        var queryParameters: [String: String]? { nil }
        var additionalHeaders: [String: String] { customHeaders }

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
