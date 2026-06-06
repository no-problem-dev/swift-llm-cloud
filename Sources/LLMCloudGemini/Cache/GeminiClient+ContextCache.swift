import Foundation
import LLMClient

extension GeminiClient: PromptCacheReleasing {}

extension GeminiClient {
    /// キャッシュ方針に従って安定プレフィックスをプロンプト文脈に解決する
    func resolvePromptContext(
        prefix: GeminiStablePrefix,
        cachePolicy: PromptCachePolicy
    ) async -> GeminiPromptContext {
        switch cachePolicy {
        case .implicit:
            return prefix.inlineContext
        case .explicitPrefix(let ttl):
            return await contextCache.resolve(prefix: prefix, ttl: ttl)
        }
    }

    /// キャッシュ失効（403/404 "CachedContent not found"）を再作成 + 1 回リトライで回復して送信する
    ///
    /// サーバー側はローカルの期限管理より早くリソースを失効させることがあるため、
    /// 生成時の失効は想定内のイベントとして扱う。
    func sendBodyRecoveringCacheLoss(
        _ body: GeminiRequestBody,
        prefix: GeminiStablePrefix,
        cachePolicy: PromptCachePolicy,
        modelId: String
    ) async throws -> (GeminiResponseBody, Int, [String: String]) {
        do {
            return try await baseProvider.sendBody(body, modelId: modelId)
        } catch GeminiCachedContentError.notFound {
            guard case .cached = body.promptContext,
                  case .explicitPrefix(let ttl) = cachePolicy else { throw GeminiCachedContentError.notFound }
            await contextCache.invalidate(prefix: prefix)
            let recovered = await contextCache.resolve(prefix: prefix, ttl: ttl)
            let retryBody = GeminiRequestBody(
                contents: body.contents,
                generationConfig: body.generationConfig,
                promptContext: recovered
            )
            return try await baseProvider.sendBody(retryBody, modelId: modelId)
        }
    }

    /// このクライアントが作成した明示キャッシュリソースを全削除する（ストレージ課金停止）
    ///
    /// セッション終了時に呼ぶ。呼ばなくても TTL で消えるが、残り時間分の課金が発生する。
    public func releasePromptCaches() async {
        await contextCache.release()
    }
}
