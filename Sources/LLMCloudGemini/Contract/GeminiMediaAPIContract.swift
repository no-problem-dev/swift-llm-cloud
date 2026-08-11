import APIContract
import Foundation
import LLMClient
import LLMCloudClient

/// Contract group for the image and video endpoints.
///
/// Covers Imagen `:predict`, Gemini image `:generateContent`, and the Veo long-running operation
/// endpoints. Authentication is the `x-goog-api-key` header and the base URL is `/v1beta/models`,
/// except for Veo operations, which sit outside `models/` and are called with a shorter base URL.
/// No key conversion is applied, because Gemini is camelCase in both directions. Errors map
/// straight to the shared error type; there is no cache classification on this path.
enum GeminiMediaAPI: APIContractGroup {
    static let basePath: String = ""
    static let auth: AuthScheme = .apiKey(headerName: "x-goog-api-key")
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = [:]

    static func decodeError(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        decoder: any APIBodyDecoder
    ) -> (any Error)? {
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? "Unknown error"
        switch statusCode {
        case 401, 403: return LLMError.unauthorized
        case 429: return LLMError.rateLimitExceeded
        case 400: return LLMError.invalidRequest(message)
        case 404: return LLMError.modelNotFound(message)
        default: return LLMError.serverError(statusCode, message)
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String; let status: String? }
        let error: Detail
    }
}

extension GeminiMediaAPI {
    /// `POST /v1beta/models/{modelId}:predict` — Imagen image generation, up to several at once.
    struct ImagenPredict: APIContract, APIInput {
        typealias Group = GeminiMediaAPI
        typealias Input = Self
        typealias Output = ImagenResponseBody
        static let method: APIMethod = .post
        static let subPath: String = "/:modelId:predict"
        let modelId: String
        let request: ImagenRequestBody
        var pathParameters: [String: String] { ["modelId": modelId] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { try encoder.encode(request) }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }

    /// `POST /v1beta/models/{modelId}:generateContent` — image generation by a Gemini image model.
    ///
    /// Images come back as inline base64 parts of a normal generation response, so the request
    /// has to ask for both text and image response modalities.
    struct GenerateImageContent: APIContract, APIInput {
        typealias Group = GeminiMediaAPI
        typealias Input = Self
        typealias Output = GeminiImageResponseBody
        static let method: APIMethod = .post
        static let subPath: String = "/:modelId:generateContent"
        let modelId: String
        let request: GeminiImageRequestBody
        var pathParameters: [String: String] { ["modelId": modelId] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { try encoder.encode(request) }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }
}

// MARK: - Imagen bodies

struct ImagenRequestBody: Encodable, Sendable {
    let instances: [Instance]
    let parameters: Parameters
    struct Instance: Encodable, Sendable { let prompt: String }
    struct Parameters: Encodable, Sendable {
        let sampleCount: Int
        let aspectRatio: String
        let personGeneration: String
    }
}

struct ImagenResponseBody: Decodable, Sendable {
    let predictions: [Prediction]
    struct Prediction: Decodable, Sendable {
        let bytesBase64Encoded: String?
        let mimeType: String?
    }
}

// MARK: - Gemini Image bodies

struct GeminiImageRequestBody: Encodable, Sendable {
    let contents: [Content]
    let generationConfig: GenerationConfig
    struct Content: Encodable, Sendable { let parts: [Part] }
    struct Part: Encodable, Sendable { let text: String }
    struct GenerationConfig: Encodable, Sendable { let responseModalities: [String] }
}

struct GeminiImageResponseBody: Decodable, Sendable {
    let candidates: [Candidate]?
    struct Candidate: Decodable, Sendable { let content: Content? }
    struct Content: Decodable, Sendable { let parts: [Part]? }
    struct Part: Decodable, Sendable { let text: String?; let inlineData: InlineData? }
    struct InlineData: Decodable, Sendable { let mimeType: String?; let data: String? }
}

// MARK: - Veo (video) — base URL is /v1beta, since operations live outside models/

extension GeminiMediaAPI {
    /// `POST /v1beta/models/{modelId}:predictLongRunning` — starts a Veo video generation job.
    ///
    /// Returns an operation name immediately, not a video: generation takes minutes and the
    /// result is collected by polling the operation.
    struct VeoGenerate: APIContract, APIInput {
        typealias Group = GeminiMediaAPI
        typealias Input = Self
        typealias Output = VeoOperationResponseBody
        static let method: APIMethod = .post
        static let subPath: String = "/models/:modelId:predictLongRunning"
        let modelId: String
        let request: VeoRequestBody
        var pathParameters: [String: String] { ["modelId": modelId] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { try encoder.encode(request) }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }

    /// `GET /v1beta/{operationName}` — polls a long-running operation for completion.
    ///
    /// The operation name from the start call is the whole path, so it is substituted as one path
    /// parameter rather than appended to a models path.
    struct VeoOperationStatus: APIContract, APIInput {
        typealias Group = GeminiMediaAPI
        typealias Input = Self
        typealias Output = VeoOperationResponseBody
        static let method: APIMethod = .get
        static let subPath: String = "/:operationName"
        let operationName: String
        var pathParameters: [String: String] { ["operationName": operationName] }
        func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
        static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError("Client-only contract") }
    }
}

struct VeoRequestBody: Encodable, Sendable {
    let instances: [Instance]
    let parameters: Parameters
    struct Instance: Encodable, Sendable { let prompt: String }
    struct Parameters: Encodable, Sendable {
        let aspectRatio: String
        let negativePrompt: String?
        let resolution: String
        let durationSeconds: Int
    }
}

/// State of a Veo operation, returned both when starting one and when polling it.
///
/// Only `name` is guaranteed. While the job runs, `done` is absent or false and there is no
/// result; once it finishes, either `error` or `response` is filled in. The result has been
/// delivered under several different key layouts, so all of the known ones are decoded and the
/// accessors look through them in turn.
struct VeoOperationResponseBody: Decodable, Sendable {
    let name: String
    let done: Bool?
    let error: ErrorDetail?
    let response: Result?

    struct ErrorDetail: Decodable, Sendable { let message: String }

    struct Result: Decodable, Sendable {
        let generateVideoResponse: GenerateVideoResponse?
        let videos: [Video]?
        let generatedVideos: [GeneratedVideoItem]?
    }
    struct GenerateVideoResponse: Decodable, Sendable { let generatedSamples: [Sample]? }
    struct Sample: Decodable, Sendable { let video: VideoInfo? }
    struct VideoInfo: Decodable, Sendable { let uri: String?; let mimeType: String? }
    struct Video: Decodable, Sendable { let gcsUri: String?; let bytesBase64Encoded: String?; let mimeType: String? }
    struct GeneratedVideoItem: Decodable, Sendable { let uri: String?; let encoding: String? }

    /// The first video reference present, whichever result layout the operation used.
    ///
    /// The value may be an HTTPS download URL, a File API path, or a `gs://` URI, so the caller
    /// still has to decide how to fetch it.
    func getVideoURL() -> String? {
        if let uri = response?.generateVideoResponse?.generatedSamples?.first?.video?.uri { return uri }
        if let gcsUri = response?.videos?.first?.gcsUri { return gcsUri }
        if let uri = response?.generatedVideos?.first?.uri { return uri }
        return nil
    }

    /// Inline video bytes, for the result layout that embeds the video instead of linking to it.
    func getVideoBase64() -> String? {
        response?.videos?.first?.bytesBase64Encoded
    }
}
