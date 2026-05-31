import APIContract
import Foundation
import LLMClient
import LLMCloudClient

/// OpenAI のメディア系エンドポイント(`/v1/audio/*`, `/v1/images/*`, `/v1/videos/*`)グループ。
/// baseURL に `/v1` を置き、各エンドポイントは相対サブパスを足す。
enum OpenAIMediaAPI: APIContractGroup {
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
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8)
            ?? "Unknown error"
        switch statusCode {
        case 401: return LLMError.unauthorized
        case 429: return LLMError.rateLimitExceeded
        case 400: return LLMError.invalidRequest(message)
        case 404: return LLMError.modelNotFound(message)
        default: return LLMError.serverError(statusCode, message)
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String; let type: String? }
        let error: Detail
    }
}

extension OpenAIMediaAPI {
    /// `POST /v1/audio/speech` — 音声(バイナリ)を生成。executeRaw で生 Data を受ける。
    struct CreateSpeech: APIContract, APIInput {
        typealias Group = OpenAIMediaAPI
        typealias Input = Self
        typealias Output = Data

        static let method: APIMethod = .post
        static let subPath: String = "audio/speech"

        let customHeaders: [String: String]
        let request: OpenAITTSRequestBody

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

struct OpenAITTSRequestBody: Encodable, Sendable {
    let model: String
    let input: String
    let voice: String
    let responseFormat: String
    let speed: Double
}

extension OpenAIMediaAPI {
    /// `POST /v1/images/generations` — 画像生成(JSON)。
    struct GenerateImage: APIContract, APIInput {
        typealias Group = OpenAIMediaAPI
        typealias Input = Self
        typealias Output = OpenAIImageResponseBody

        static let method: APIMethod = .post
        static let subPath: String = "images/generations"

        let customHeaders: [String: String]
        let request: OpenAIImageRequestBody

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

/// キー変換は mediaClient(.snakeCase)に委ねる(明示 CodingKeys を持たない)。
struct OpenAIImageRequestBody: Encodable, Sendable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    let quality: String?
    let responseFormat: String?
    let outputFormat: String?
}

struct OpenAIImageResponseBody: Decodable, Sendable {
    let created: Int
    let data: [Item]

    struct Item: Decodable, Sendable {
        let b64Json: String?
        let url: String?
        let revisedPrompt: String?
    }
}
