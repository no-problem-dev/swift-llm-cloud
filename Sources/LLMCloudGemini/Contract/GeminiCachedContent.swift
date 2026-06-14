import APIContract
import CryptoKit
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Stable Prefix

/// 明示キャッシュの対象となる「安定プレフィックス」
///
/// model + systemInstruction + tools + toolConfig の組。
/// この 4 つが同一なら同じ `cachedContents` リソースを再利用できる
/// （キャッシュはモデル文字列にも固定されるため model を identity に含める）。
struct GeminiStablePrefix: Sendable {
    let model: String
    let systemInstruction: GeminiContent?
    let tools: [GeminiTool]?
    let toolConfig: GeminiToolConfig?

    /// 正準 JSON（sortedKeys）の SHA-256。冪等なキャッシュ作成の identity
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

    /// このプレフィックスを inline 送信する文脈（キャッシュ不使用・フォールバック先）
    var inlineContext: GeminiPromptContext {
        .inline(systemInstruction: systemInstruction, tools: tools, toolConfig: toolConfig)
    }

    /// このプレフィックスからキャッシュ作成ボディを構築
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

/// キャッシュの有効期限。API 仕様で `ttl` と `expireTime` は union（どちらか一方）
enum GeminiCacheExpiration: Sendable, Hashable {
    /// 今からの生存期間。`"3600s"` 形式にエンコードされる
    case ttl(Duration)
    /// 絶対期限（RFC 3339）
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

/// Gemini API の RFC 3339 タイムスタンプ変換
enum GeminiRFC3339 {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// fractional seconds あり/なし両対応でパース
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

/// `POST /v1beta/cachedContents` のリクエストボディ
///
/// 作成後は expiration 以外すべて不変（変更するには新しいキャッシュを作る）。
/// 更新用の `GeminiCachedContentPatchBody` とは意図的に別型。
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

/// `PATCH /v1beta/cachedContents/{id}` のリクエストボディ（期限のみ可変）
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

    /// PATCH の updateMask（API リファレンスで必須宣言）
    var updateMask: String {
        switch expiration {
        case .ttl: return "ttl"
        case .expireTime: return "expireTime"
        }
    }
}

// MARK: - Resource

/// `cachedContents` リソース（API レスポンス）
///
/// contents/systemInstruction/tools/toolConfig は input-only のためレスポンスに含まれない。
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

    /// `cachedContents/{id}` の id 部分（パスパラメータ用）
    var resourceId: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    var expireDate: Date? {
        GeminiRFC3339.parse(expireTime)
    }
}

/// `GET /v1beta/cachedContents` のレスポンス
struct GeminiCachedContentListResponse: Decodable, Sendable {
    let cachedContents: [GeminiCachedContentResource]?
    let nextPageToken: String?
}

// MARK: - Error Classification

/// cachedContents 操作・参照に固有のエラー
///
/// API はこれらを汎用の 400/403/404 + メッセージ文字列でしか表現しないため、
/// メッセージを分類して回復戦略（inline フォールバック / 再作成）に接続する。
public enum GeminiCachedContentError: Error, Sendable, Equatable {
    /// プレフィックスが最小キャッシュトークン数未満（400）。inline フォールバックで回復
    case belowMinimumTokenCount(actual: Int?, minimum: Int?)
    /// 参照したキャッシュが失効・削除済み（403/404）。再作成で回復
    case notFound
}

enum GeminiCacheErrorClassifier {
    /// エラーレスポンスを cachedContents 固有エラーに分類する。該当しなければ nil
    static func classify(statusCode: Int, message: String) -> GeminiCachedContentError? {
        switch statusCode {
        case 400:
            // 文言は時期で揺れる:
            //   旧 "The cached content is of 151 tokens. The minimum token count to start caching is 1024."
            //   現 "Cached content is too small. total_token_count=575, min_total_token_count=1024"
            // どちらも「最小キャッシュトークン数未満」という同一の恒久条件として分類する。
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

/// `cachedContents` リソースの CRUD エンドポイント群
///
/// baseURL は `/v1beta`（`/models` の外）。認証は generateContent と同じ `x-goog-api-key` ヘッダー。
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
    /// `POST /v1beta/cachedContents` — キャッシュ作成
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

    /// `GET /v1beta/cachedContents/{id}` — キャッシュ取得
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

    /// `GET /v1beta/cachedContents` — キャッシュ一覧
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

    /// `PATCH /v1beta/cachedContents/{id}` — 期限の更新（ttl は「今から」の相対）
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

    /// `DELETE /v1beta/cachedContents/{id}` — キャッシュ削除（ストレージ課金停止）
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
