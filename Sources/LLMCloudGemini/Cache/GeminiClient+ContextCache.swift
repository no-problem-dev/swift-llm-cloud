import Foundation
import LLMClient

extension GeminiClient: PromptCacheReleasing {}

extension GeminiClient {
    /// Turns a stable prefix into a prompt context according to the caller's cache policy.
    ///
    /// An implicit policy always sends the prefix inline: Gemini may still cache it automatically,
    /// but no `cachedContents` resource is created and nothing is billed for storage. An explicit
    /// policy goes through the cache store, which may still answer with the inline form.
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

    /// Sends a request body, recovering once from a cache that the server no longer has.
    ///
    /// The server can drop a cache resource earlier than local expiry tracking expects, so a 403
    /// or 404 naming `CachedContent` is an expected outcome rather than an error: the entry is
    /// invalidated, a replacement is resolved, and the same contents are sent again. The retry
    /// happens only for a request that actually referenced a cache under an explicit policy;
    /// anything else rethrows, and there is never more than one retry.
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

    /// Deletes the explicit cache resources this client created, ending their storage billing.
    ///
    /// Call it when a session ends. Skipping it is safe but not free: the resources survive until
    /// their TTL runs out and are billed for storage the whole time.
    public func releasePromptCaches() async {
        await contextCache.release()
    }
}
