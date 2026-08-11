import APIContract
import Foundation
import LLMClient
import LLMCloudClient

/// Contract group for the OpenAI audio, image, and video endpoints.
///
/// The base URL is `/v1` and each endpoint appends its own relative sub-path. Unlike the
/// Responses group these bodies carry no explicit coding keys, so the client applies snake-case
/// conversion. Errors are decoded into `LLMError` without rate-limit information: media calls
/// are not driven by the retry runner.
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
    /// `POST /v1/audio/speech` — synthesizes speech.
    ///
    /// The reply is the encoded audio itself rather than JSON, so this contract is executed raw
    /// and its output is the undecoded bytes.
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
    /// `POST /v1/images/generations` — generates images and returns them as JSON.
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

/// Body of an image generation request.
///
/// It declares no coding keys on purpose: the media client encodes with snake-case conversion,
/// which turns `responseFormat` into `response_format` and `outputFormat` into `output_format`.
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

    /// One generated image, delivered either inline or as a link.
    ///
    /// Which field is populated depends on the model: GPT-Image always answers with base64,
    /// while DALL·E returns a short-lived URL unless `response_format` asked for base64.
    /// `revisedPrompt` is the prompt the model rewrote for itself, and it is absent on models
    /// that do not rewrite prompts.
    struct Item: Decodable, Sendable {
        let b64Json: String?
        let url: String?
        let revisedPrompt: String?
    }
}

extension OpenAIMediaAPI {
    /// `POST /v1/videos` — starts a video generation job.
    ///
    /// The call returns as soon as the job is queued; the frames are produced asynchronously and
    /// have to be polled for.
    struct CreateVideo: APIContract, APIInput {
        typealias Group = OpenAIMediaAPI
        typealias Input = Self
        typealias Output = SoraVideoResponseBody
        static let method: APIMethod = .post
        static let subPath: String = "videos"
        let request: SoraVideoRequestBody
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { try encoder.encode(request) }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }

    /// `GET /v1/videos/{id}` — reads the current state of a job.
    struct GetVideoStatus: APIContract, APIInput {
        typealias Group = OpenAIMediaAPI
        typealias Input = Self
        typealias Output = SoraVideoResponseBody
        static let method: APIMethod = .get
        static let subPath: String = "videos/:videoId"
        let videoId: String
        var pathParameters: [String: String] { ["videoId": videoId] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }

    /// `GET /v1/videos/{id}/content` — downloads the finished video.
    ///
    /// The reply is the MP4 payload rather than JSON, so this contract is executed raw and its
    /// output is the undecoded bytes.
    struct DownloadVideo: APIContract, APIInput {
        typealias Group = OpenAIMediaAPI
        typealias Input = Self
        typealias Output = Data
        static let method: APIMethod = .get
        static let subPath: String = "videos/:videoId/content"
        let videoId: String
        var pathParameters: [String: String] { ["videoId": videoId] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }
}

struct SoraVideoRequestBody: Encodable, Sendable {
    let model: String
    let prompt: String
    let seconds: String
    let size: String
}

/// State of a Sora video job.
///
/// It declares no coding keys on purpose: the media client decodes with snake-case conversion,
/// which maps `created_at` onto `createdAt`. `status` is kept as the raw string OpenAI sent so an
/// unfamiliar value does not fail the decode, `progress` is a percentage from 0 to 100, and
/// `error` is populated only once the job has failed.
struct SoraVideoResponseBody: Decodable, Sendable {
    let id: String
    let status: String
    let createdAt: Int
    let progress: Int?
    let error: Detail?

    struct Detail: Decodable, Sendable {
        let message: String
    }
}
