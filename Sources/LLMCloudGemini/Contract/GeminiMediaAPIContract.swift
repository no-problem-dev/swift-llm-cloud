import APIContract
import Foundation
import LLMClient
import LLMCloudClient

/// Gemini のメディア系エンドポイント(Imagen `:predict`, Gemini Image `:generateContent`,
/// Veo files API)グループ。認証は `x-goog-api-key` ヘッダー、baseURL は `/v1beta/models`。
/// キー変換なし(`.default`): Gemini はリクエスト/レスポンスとも camelCase。
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
    /// `POST /v1beta/models/{modelId}:predict` — Imagen 画像生成。
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

    /// `POST /v1beta/models/{modelId}:generateContent` — Gemini Image 生成。
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

// MARK: - Veo (動画) — baseURL は /v1beta(operations は models/ の外)

extension GeminiMediaAPI {
    /// `POST /v1beta/models/{modelId}:predictLongRunning` — Veo 動画生成ジョブを開始。
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

    /// `GET /v1beta/{operationName}` — 長時間オペレーションのステータス。
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

    func getVideoURL() -> String? {
        if let uri = response?.generateVideoResponse?.generatedSamples?.first?.video?.uri { return uri }
        if let gcsUri = response?.videos?.first?.gcsUri { return gcsUri }
        if let uri = response?.generatedVideos?.first?.uri { return uri }
        return nil
    }

    func getVideoBase64() -> String? {
        response?.videos?.first?.bytesBase64Encoded
    }
}
