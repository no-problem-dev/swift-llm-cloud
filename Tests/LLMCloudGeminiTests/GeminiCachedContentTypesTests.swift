import Foundation
import Testing
import LLMClient
@testable import LLMCloudGemini

@Suite("Gemini cachedContents 型とエンコード")
struct GeminiCachedContentTypesTests {

    private var sampleTools: [GeminiTool] {
        [GeminiTool(functionDeclarations: [
            GeminiFunctionDeclaration(
                name: "lookup",
                description: "look up",
                parameters: JSONSchema(type: .object, properties: ["q": JSONSchema(type: .string)], required: ["q"])
            )
        ])]
    }

    private var sampleInstruction: GeminiContent {
        GeminiContent(role: "user", parts: [GeminiPart(text: "you are a researcher")])
    }

    private func encodeToString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    // MARK: - GeminiRequestBody の排他不変条件

    @Test("inline 文脈は systemInstruction/tools/toolConfig を含み cachedContent を含まない")
    func inlineContextEncoding() throws {
        let body = GeminiRequestBody(
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: "hi")])],
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 100, temperature: nil),
            promptContext: .inline(
                systemInstruction: sampleInstruction,
                tools: sampleTools,
                toolConfig: GeminiToolConfig(functionCallingConfig: GeminiFunctionCallingConfig(mode: "AUTO", allowedFunctionNames: nil))
            )
        )
        let json = try encodeToString(body)
        #expect(json.contains("systemInstruction"))
        #expect(json.contains("functionDeclarations"))
        #expect(json.contains("toolConfig"))
        #expect(!json.contains("cachedContent"))
    }

    @Test("cached 文脈は cachedContent のみを含み、prefix 系フィールドを一切含まない")
    func cachedContextEncoding() throws {
        let body = GeminiRequestBody(
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: "hi")])],
            generationConfig: GeminiGenerationConfig(maxOutputTokens: 100, temperature: nil),
            promptContext: .cached(name: "cachedContents/abc-123")
        )
        let json = try encodeToString(body)
        #expect(json.contains(#""cachedContent":"cachedContents\/abc-123""#) || json.contains(#""cachedContent":"cachedContents/abc-123""#))
        #expect(!json.contains("systemInstruction"))
        #expect(!json.contains("tools"))
        #expect(!json.contains("toolConfig"))
    }

    // MARK: - CreateBody / PatchBody

    @Test("CreateBody は models/ 接頭辞付き model と ttl 秒文字列をエンコード")
    func createBodyEncoding() throws {
        let prefix = GeminiStablePrefix(
            model: "gemini-2.5-flash",
            systemInstruction: sampleInstruction,
            tools: sampleTools,
            toolConfig: nil
        )
        let body = prefix.makeCreateBody(expiration: .ttl(.seconds(3600)), displayName: "test")
        let json = try encodeToString(body)
        #expect(json.contains(#""model":"models\/gemini-2.5-flash""# ) || json.contains(#""model":"models/gemini-2.5-flash""#))
        #expect(json.contains(#""ttl":"3600s""#))
        #expect(!json.contains("expireTime"))
        #expect(json.contains("systemInstruction"))
        #expect(json.contains("functionDeclarations"))
    }

    @Test("expireTime は RFC3339 でエンコードされ ttl と排他")
    func expireTimeEncoding() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let body = GeminiCachedContentCreateBody(
            model: "models/gemini-2.5-flash",
            contents: nil, systemInstruction: nil, tools: nil, toolConfig: nil,
            displayName: nil,
            expiration: .expireTime(date)
        )
        let json = try encodeToString(body)
        #expect(json.contains("expireTime"))
        #expect(!json.contains("\"ttl\""))
        #expect(json.contains("2026-")) // RFC3339 文字列
    }

    @Test("PatchBody の updateMask は expiration の種別に一致")
    func patchBodyUpdateMask() {
        #expect(GeminiCachedContentPatchBody(expiration: .ttl(.seconds(60))).updateMask == "ttl")
        #expect(GeminiCachedContentPatchBody(expiration: .expireTime(Date())).updateMask == "expireTime")
    }

    // MARK: - StablePrefix identity

    @Test("contentHash は決定的（同一内容 → 同一ハッシュ）")
    func contentHashDeterministic() {
        let make = {
            GeminiStablePrefix(
                model: "gemini-2.5-flash",
                systemInstruction: sampleInstruction,
                tools: sampleTools,
                toolConfig: nil
            )
        }
        #expect(make().contentHash == make().contentHash)
        #expect(make().contentHash.count == 64) // SHA-256 hex
    }

    @Test("contentHash は model・instruction・tools の差分に反応する")
    func contentHashSensitivity() {
        let base = GeminiStablePrefix(model: "gemini-2.5-flash", systemInstruction: sampleInstruction, tools: sampleTools, toolConfig: nil)
        let differentModel = GeminiStablePrefix(model: "gemini-3.5-flash", systemInstruction: sampleInstruction, tools: sampleTools, toolConfig: nil)
        let differentPrompt = GeminiStablePrefix(
            model: "gemini-2.5-flash",
            systemInstruction: GeminiContent(role: "user", parts: [GeminiPart(text: "other")]),
            tools: sampleTools, toolConfig: nil
        )
        let noTools = GeminiStablePrefix(model: "gemini-2.5-flash", systemInstruction: sampleInstruction, tools: nil, toolConfig: nil)
        #expect(base.contentHash != differentModel.contentHash)
        #expect(base.contentHash != differentPrompt.contentHash)
        #expect(base.contentHash != noTools.contentHash)
    }

    // MARK: - エラー分類

    @Test("最小トークン未満の 400 を分類し実測値を抽出")
    func classifyBelowMinimum() {
        let message = "The cached content is of 151 tokens. The minimum token count to start caching is 1024."
        let error = GeminiCacheErrorClassifier.classify(statusCode: 400, message: message)
        #expect(error == .belowMinimumTokenCount(actual: 151, minimum: 1024))
    }

    @Test("CachedContent not found を 403/404 の双方で分類")
    func classifyNotFound() {
        let message = "CachedContent not found (or permission denied)."
        #expect(GeminiCacheErrorClassifier.classify(statusCode: 403, message: message) == .notFound)
        #expect(GeminiCacheErrorClassifier.classify(statusCode: 404, message: message) == .notFound)
    }

    @Test("無関係なエラーは分類しない")
    func classifyUnrelated() {
        #expect(GeminiCacheErrorClassifier.classify(statusCode: 400, message: "Invalid argument: contents") == nil)
        #expect(GeminiCacheErrorClassifier.classify(statusCode: 403, message: "API key invalid") == nil)
        #expect(GeminiCacheErrorClassifier.classify(statusCode: 500, message: "CachedContent not found") == nil)
    }

    // MARK: - RFC3339

    @Test("RFC3339 は fractional seconds あり/なし両対応でパース")
    func rfc3339Parsing() {
        #expect(GeminiRFC3339.parse("2026-06-06T15:01:23.123456Z") != nil)
        #expect(GeminiRFC3339.parse("2026-06-06T15:01:23Z") != nil)
        #expect(GeminiRFC3339.parse("not a date") == nil)
    }

    @Test("リソースの resourceId は name の末尾セグメント")
    func resourceIdExtraction() throws {
        let json = Data(#"""
        {"name": "cachedContents/abc-123", "model": "models/gemini-2.5-flash",
         "expireTime": "2026-06-06T15:01:23Z",
         "usageMetadata": {"totalTokenCount": 12345}}
        """#.utf8)
        let resource = try JSONDecoder().decode(GeminiCachedContentResource.self, from: json)
        #expect(resource.resourceId == "abc-123")
        #expect(resource.expireDate != nil)
        #expect(resource.usageMetadata?.totalTokenCount == 12345)
    }
}
