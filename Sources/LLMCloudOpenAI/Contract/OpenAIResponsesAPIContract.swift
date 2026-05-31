import APIContract
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAI Responses API Group

/// OpenAI `/v1/responses` API のグループ定義。
///
/// - Auth: `Authorization: Bearer`
/// - basePath は空（エンドポイント URL に完全パスを含む）
/// - キー変換なし(`.default`): リクエスト/レスポンス共に明示的 CodingKeys を持つため
///   convertToSnakeCase/convertFromSnakeCase を適用してはならない。
/// - Custom Error Decoding: LLMError + RateLimitAwareError(x-ratelimit-* ヘッダー)
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
    /// `/v1/responses` 作成エンドポイント（非ストリーミング）。
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
