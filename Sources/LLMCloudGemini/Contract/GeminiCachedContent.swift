import APIContract
import CryptoKit
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Stable Prefix

/// The part of a request that can be cached explicitly, because it does not change between turns.
///
/// Groups the model id with the system instruction, tools, and tool config. Two requests sharing
/// all four can share one `cachedContents` resource. The model belongs in the identity because a
/// Gemini cache is bound to the exact model string it was created with, including a pinned
/// version suffix, and is unusable from any other model.
struct GeminiStablePrefix: Sendable {
    let model: String
    let systemInstruction: GeminiContent?
    let tools: [GeminiTool]?
    let toolConfig: GeminiToolConfig?

    /// SHA-256 of the canonical JSON encoding, used as the cache identity.
    ///
    /// Keys are sorted so that two structurally identical prefixes hash alike regardless of
    /// encoding order, which is what makes cache creation idempotent. If encoding fails the
    /// literal `"encoding-failed"` is returned, which collapses every unencodable prefix onto one
    /// key rather than crashing.
    var contentHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Canonical: Encodable {
            let model: String
            let systemInstruction: GeminiContent?
            let tools: [GeminiTool]?
            let toolConfig: GeminiToolConfig?
        }
        let canonical = Canonical(
            model: model,
            systemInstruction: systemInstruction,
            tools: tools,
            toolConfig: toolConfig
        )
        guard let data = try? encoder.encode(canonical) else { return "encoding-failed" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The same prefix sent in the request body instead of cached, used as the fallback path.
    var inlineContext: GeminiPromptContext {
        .inline(systemInstruction: systemInstruction, tools: tools, toolConfig: toolConfig)
    }

    /// Builds the creation body for this prefix, qualifying the model id as `models/{id}`.
    ///
    /// No `contents` are cached, only the prefix parts, so the conversation itself is still sent
    /// with every request.
    func makeCreateBody(expiration: GeminiCacheExpiration, displayName: String? = nil) -> GeminiCachedContentCreateBody {
        GeminiCachedContentCreateBody(
            model: "models/\(model)",
            contents: nil,
            systemInstruction: systemInstruction,
            tools: tools,
            toolConfig: toolConfig,
            displayName: displayName,
            expiration: expiration
        )
    }
}

// MARK: - Expiration

/// When a cache resource expires, expressed the way the API allows.
///
/// Gemini treats `ttl` and `expireTime` as a union: sending both is invalid, which the enum makes
/// unrepresentable.
enum GeminiCacheExpiration: Sendable, Hashable {
    /// Lifetime counted from now, encoded in the `"3600s"` form Gemini expects.
    ///
    /// A TTL is always relative to the moment the server receives it, so reusing the same value
    /// on a later PATCH extends the resource rather than restoring an original deadline.
    case ttl(Duration)
    /// Absolute deadline, encoded as RFC 3339.
    case expireTime(Date)
}

extension GeminiCacheExpiration {
    var ttlString: String? {
        guard case .ttl(let duration) = self else { return nil }
        return "\(duration.components.seconds)s"
    }

    var expireTimeString: String? {
        guard case .expireTime(let date) = self else { return nil }
        return GeminiRFC3339.format(date)
    }
}

/// RFC 3339 timestamp conversion for the Gemini wire format.
enum GeminiRFC3339 {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Parses a timestamp with or without fractional seconds, since Gemini sends both forms.
    static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - Bodies

/// Body for creating a cache resource.
///
/// Everything except the expiration is frozen at creation: changing the model, system
/// instruction, tools, or tool config means creating a new cache. Updates therefore use a
/// deliberately separate type, ``GeminiCachedContentPatchBody``, that can express nothing else.
/// Creation fails with a 400 when the prefix is below the model's minimum cacheable token count.
struct GeminiCachedContentCreateBody: Encodable, Sendable {
    let model: String
    let contents: [GeminiContent]?
    let systemInstruction: GeminiContent?
    let tools: [GeminiTool]?
    let toolConfig: GeminiToolConfig?
    let displayName: String?
    let expiration: GeminiCacheExpiration

    enum CodingKeys: String, CodingKey {
        case model, contents, systemInstruction, tools, toolConfig, displayName
        case ttl, expireTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(contents, forKey: .contents)
        try container.encodeIfPresent(systemInstruction, forKey: .systemInstruction)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolConfig, forKey: .toolConfig)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(expiration.ttlString, forKey: .ttl)
        try container.encodeIfPresent(expiration.expireTimeString, forKey: .expireTime)
    }
}

/// Body for updating a cache resource; the expiration is the only mutable field.
struct GeminiCachedContentPatchBody: Encodable, Sendable {
    let expiration: GeminiCacheExpiration

    enum CodingKeys: String, CodingKey {
        case ttl, expireTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(expiration.ttlString, forKey: .ttl)
        try container.encodeIfPresent(expiration.expireTimeString, forKey: .expireTime)
    }

    /// Field mask naming the single field being patched, which the API requires on every PATCH.
    var updateMask: String {
        switch expiration {
        case .ttl: return "ttl"
        case .expireTime: return "expireTime"
        }
    }
}

// MARK: - Resource

/// A cache resource as the API returns it.
///
/// The cached material itself never comes back: contents, system instruction, tools, and tool
/// config are input-only. What is readable is the identity, the expiry, and the token count that
/// says how much of the prompt the cache covers.
struct GeminiCachedContentResource: Decodable, Sendable {
    let name: String
    let model: String
    let displayName: String?
    let createTime: String?
    let updateTime: String?
    let expireTime: String
    let usageMetadata: UsageMetadata?

    struct UsageMetadata: Decodable, Sendable {
        let totalTokenCount: Int?
    }

    /// The id portion of the `cachedContents/{id}` name, for use as a path parameter.
    var resourceId: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    var expireDate: Date? {
        GeminiRFC3339.parse(expireTime)
    }
}

/// One page of the cache listing, along with the token for the next page if there is one.
struct GeminiCachedContentListResponse: Decodable, Sendable {
    let cachedContents: [GeminiCachedContentResource]?
    let nextPageToken: String?
}

// MARK: - Error Classification

/// Failures specific to creating or referencing a cache resource.
///
/// Gemini reports both as a plain 400, 403, or 404 with prose in the message, so the message is
/// classified into these cases and each is wired to its own recovery: fall back to inline, or
/// recreate the cache.
public enum GeminiCachedContentError: Error, Sendable, Equatable {
    /// The prefix is shorter than the model's minimum cacheable token count, reported as a 400.
    ///
    /// A permanent property of that prefix, not a transient failure: retrying the same content
    /// fails identically, so recovery is to send it inline instead. The counts are parsed out of
    /// the message and may be missing.
    case belowMinimumTokenCount(actual: Int?, minimum: Int?)
    /// The referenced cache has expired or been deleted, reported as a 403 or 404.
    ///
    /// Recovered by creating a fresh cache and retrying once.
    case notFound
}

/// Turns Gemini's prose error messages into the cache-specific error cases.
enum GeminiCacheErrorClassifier {
    /// Classifies an error response, returning nil when it is not cache-specific.
    ///
    /// Matching is on message text because the status code alone cannot distinguish these from
    /// any other bad request or missing resource. The token counts are read as the first two
    /// integers in the message, so their presence depends on the wording the server used.
    static func classify(statusCode: Int, message: String) -> GeminiCachedContentError? {
        switch statusCode {
        case 400:
            // The wording has changed over time:
            //   older: "The cached content is of 151 tokens. The minimum token count to start caching is 1024."
            //   newer: "Cached content is too small. total_token_count=575, min_total_token_count=1024"
            // Both mean the same permanent condition, so both classify as below-minimum.
            let lowered = message.lowercased()
            guard lowered.contains("minimum token count") || lowered.contains("min_total_token_count") else { return nil }
            let numbers = extractIntegers(from: message)
            return .belowMinimumTokenCount(actual: numbers.first, minimum: numbers.count > 1 ? numbers[1] : nil)
        case 403, 404:
            guard message.contains("CachedContent") else { return nil }
            return .notFound
        default:
            return nil
        }
    }

    private static func extractIntegers(from message: String) -> [Int] {
        message.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}

// MARK: - API Contracts

/// CRUD endpoints for cache resources.
///
/// These live at `/v1beta/cachedContents`, outside `/models`, so they need a base URL one
/// component shorter than generateContent's. Authentication is the same `x-goog-api-key` header.
/// Error decoding routes cache-specific failures to ``GeminiCachedContentError`` before falling
/// back to the shared error mapping.
enum GeminiCacheAPI: APIContractGroup {
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
        let message = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? "Unknown error"
        if let cacheError = GeminiCacheErrorClassifier.classify(statusCode: statusCode, message: message) {
            return cacheError
        }
        switch statusCode {
        case 401, 403: return LLMError.unauthorized
        case 400: return LLMError.invalidRequest(message)
        case 404: return LLMError.modelNotFound(message)
        case 429: return LLMError.rateLimitExceeded
        default: return LLMError.serverError(statusCode, message)
        }
    }
}

extension GeminiCacheAPI {
    /// `POST /v1beta/cachedContents` — creates a cache resource and starts storage billing.
    struct Create: APIContract, APIInput {
        typealias Group = GeminiCacheAPI
        typealias Input = Self
        typealias Output = GeminiCachedContentResource

        static let method: APIMethod = .post
        static let subPath: String = "/cachedContents"

        let request: GeminiCachedContentCreateBody

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

    /// `GET /v1beta/cachedContents/{id}` — reads one cache resource's metadata.
    struct Get: APIContract, APIInput {
        typealias Group = GeminiCacheAPI
        typealias Input = Self
        typealias Output = GeminiCachedContentResource

        static let method: APIMethod = .get
        static let subPath: String = "/cachedContents/:cacheId"

        let cacheId: String

        var pathParameters: [String: String] { ["cacheId": cacheId] }

        static func decode(
            pathParameters: [String: String],
            queryParameters: [String: String],
            body: Data?,
            decoder: any APIBodyDecoder
        ) throws -> Self {
            fatalError("Client-only contract")
        }
    }

    /// `GET /v1beta/cachedContents` — lists the caches on the API key, page by page.
    struct List: APIContract, APIInput {
        typealias Group = GeminiCacheAPI
        typealias Input = Self
        typealias Output = GeminiCachedContentListResponse

        static let method: APIMethod = .get
        static let subPath: String = "/cachedContents"

        let pageSize: Int?
        let pageToken: String?

        var queryParameters: [String: String]? {
            var params: [String: String] = [:]
            if let pageSize { params["pageSize"] = "\(pageSize)" }
            if let pageToken { params["pageToken"] = pageToken }
            return params.isEmpty ? nil : params
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

    /// `PATCH /v1beta/cachedContents/{id}` — moves the expiry; a TTL counts from the server's now.
    struct Update: APIContract, APIInput {
        typealias Group = GeminiCacheAPI
        typealias Input = Self
        typealias Output = GeminiCachedContentResource

        static let method: APIMethod = .patch
        static let subPath: String = "/cachedContents/:cacheId"

        let cacheId: String
        let request: GeminiCachedContentPatchBody

        var pathParameters: [String: String] { ["cacheId": cacheId] }
        var queryParameters: [String: String]? { ["updateMask": request.updateMask] }

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

    /// `DELETE /v1beta/cachedContents/{id}` — deletes a cache and stops its storage billing.
    struct Delete: APIContract, APIInput {
        typealias Group = GeminiCacheAPI
        typealias Input = Self
        typealias Output = EmptyOutput

        static let method: APIMethod = .delete
        static let subPath: String = "/cachedContents/:cacheId"

        let cacheId: String

        var pathParameters: [String: String] { ["cacheId": cacheId] }

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
