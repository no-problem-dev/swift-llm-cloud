import APIClient
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Cache Events

/// Observable lifecycle events of the explicit prompt cache.
///
/// Caching never fails a request, so these events are the only way to see what it actually did:
/// whether a prefix was cached, reused, or quietly sent inline instead.
public enum GeminiCacheEvent: Sendable {
    /// A new cache resource was created; the token count is what the server says it covers.
    case created(name: String, tokenCount: Int?)
    /// An existing cache resource was referenced again.
    case reused(name: String)
    /// The expiry of an existing resource was pushed back.
    case extended(name: String, until: Date?)
    /// The prefix was sent inline instead of cached, with the reason it could not be cached.
    ///
    /// Also emitted when a delete fails during release, since that too leaves the caller without
    /// the cache behaviour it asked for.
    case fallbackInline(reason: String)
    /// An expired cache was recreated and the request continued.
    case recovered(name: String)
    /// A cache resource was deleted and its storage billing stopped.
    case deleted(name: String)
}

public typealias GeminiCacheEventHandler = @Sendable (GeminiCacheEvent) -> Void

// MARK: - GeminiContextCacheStore

/// Owns the `cachedContents` resources created for one client.
///
/// Keyed by the content hash of the stable prefix (model, system instruction, tools, tool
/// config), it provides:
/// - **Idempotent creation.** Concurrent resolves of the same prefix join one creation instead of
///   racing to create duplicates.
/// - **Expiry management.** A resource close to expiry is extended by PATCH, and one judged
///   already expired is recreated. Gemini TTLs are relative to the server's clock.
/// - **Permanent fallback.** A prefix rejected for being under the minimum cacheable token count
///   is remembered, and every later resolve for it returns inline without another API call.
/// - **Release.** Deleting the resources stops storage billing, which continues for the remaining
///   TTL otherwise.
///
/// Resolution never throws. The cache is an optimization, so any failure degrades to sending the
/// prefix inline; the event handler is where that becomes visible.
actor GeminiContextCacheStore {
    private let apiClient: APIClientImpl
    private let eventHandler: GeminiCacheEventHandler?

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<GeminiPromptContext, Never>] = [:]

    private enum Entry {
        case active(name: String, expireDate: Date?)
        case inlineOnly(reason: String)
    }

    /// Safety margin, in seconds, before the recorded expiry at which a cache is treated as gone.
    ///
    /// The server can expire a resource earlier than the local clock predicts, so the last minute
    /// of a cache's life is not trusted.
    private static let expiryMargin: TimeInterval = 60
    /// Remaining lifetime, in seconds, below which the expiry is extended by PATCH.
    private static let extensionThreshold: TimeInterval = 300

    init(apiClient: APIClientImpl, eventHandler: GeminiCacheEventHandler?) {
        self.apiClient = apiClient
        self.eventHandler = eventHandler
    }

    // MARK: - Resolve

    /// Resolves a stable prefix to the prompt context a request should use.
    ///
    /// Returns a cached reference when one exists or can be created, and the inline form
    /// otherwise. Creating a cache costs one extra round trip the first time a prefix is seen.
    ///
    /// - Parameters:
    ///   - prefix: The prefix to cache; its content hash is the cache identity.
    ///   - ttl: Lifetime requested at creation, and reused when extending an existing resource.
    func resolve(prefix: GeminiStablePrefix, ttl: Duration) async -> GeminiPromptContext {
        let key = prefix.contentHash

        if let task = inFlight[key] {
            return await task.value
        }

        switch entries[key] {
        case .inlineOnly:
            return prefix.inlineContext

        case .active(let name, let expireDate):
            let remaining = (expireDate ?? .distantPast).timeIntervalSinceNow
            if remaining < Self.expiryMargin {
                // Treat it as already gone and build a replacement.
                entries[key] = nil
                return await runExclusively(key: key) { [self] in
                    await create(prefix: prefix, ttl: ttl, isRecovery: true)
                }
            }
            if remaining < Self.extensionThreshold {
                await extend(key: key, name: name, ttl: ttl)
            }
            eventHandler?(.reused(name: name))
            return .cached(name: name)

        case nil:
            return await runExclusively(key: key) { [self] in
                await create(prefix: prefix, ttl: ttl, isRecovery: false)
            }
        }
    }

    /// Forgets the cache recorded for a prefix after the server reported it missing.
    ///
    /// Called from the generation paths when a request fails with a cache 403 or 404, so the next
    /// resolve creates a replacement instead of referencing a name the server no longer knows.
    /// A prefix already marked inline-only is left as it is.
    func invalidate(prefix: GeminiStablePrefix) {
        if case .active = entries[prefix.contentHash] {
            entries[prefix.contentHash] = nil
        }
    }

    /// Deletes every cache resource this store created, ending their storage billing.
    ///
    /// Meant for the end of a session. Deletion failures are reported as fallback events rather
    /// than thrown, because an undeletable resource still disappears on its own at TTL.
    func release() async {
        for (key, entry) in entries {
            guard case .active(let name, _) = entry else { continue }
            entries[key] = nil
            do {
                _ = try await apiClient.executeWithResponse(
                    GeminiCacheAPI.Delete(cacheId: Self.resourceId(of: name))
                )
                eventHandler?(.deleted(name: name))
            } catch {
                // An undeletable resource (already expired, for instance) still goes away at TTL,
                // so this is not worth failing on — but it is worth seeing.
                eventHandler?(.fallbackInline(reason: "delete failed for \(name): \(error)"))
            }
        }
    }

    // MARK: - Private

    /// Runs an operation for a key so that concurrent callers share its single result.
    ///
    /// The actor suspends at every await, so without this two resolves of the same prefix would
    /// both see no entry and both create a cache.
    private func runExclusively(
        key: String,
        operation: @escaping @Sendable () async -> GeminiPromptContext
    ) async -> GeminiPromptContext {
        let task = Task { await operation() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func create(prefix: GeminiStablePrefix, ttl: Duration, isRecovery: Bool) async -> GeminiPromptContext {
        let key = prefix.contentHash
        let body = prefix.makeCreateBody(
            expiration: .ttl(ttl),
            displayName: "swift-llm-cloud/\(key.prefix(12))"
        )
        do {
            let response = try await apiClient.executeWithResponse(GeminiCacheAPI.Create(request: body))
            let resource = response.output
            entries[key] = .active(name: resource.name, expireDate: resource.expireDate)
            if isRecovery {
                eventHandler?(.recovered(name: resource.name))
            } else {
                eventHandler?(.created(name: resource.name, tokenCount: resource.usageMetadata?.totalTokenCount))
            }
            return .cached(name: resource.name)
        } catch let error as GeminiCachedContentError {
            // Being under the minimum token count is permanent for this prefix: remember it and
            // stop attempting creation.
            if case .belowMinimumTokenCount = error {
                entries[key] = .inlineOnly(reason: "\(error)")
            }
            eventHandler?(.fallbackInline(reason: "\(error)"))
            return prefix.inlineContext
        } catch {
            // Transient failure (rate limit, network): send inline this once without recording
            // anything, so the next request tries to create the cache again.
            eventHandler?(.fallbackInline(reason: "\(error)"))
            return prefix.inlineContext
        }
    }

    private func extend(key: String, name: String, ttl: Duration) async {
        do {
            let response = try await apiClient.executeWithResponse(
                GeminiCacheAPI.Update(
                    cacheId: Self.resourceId(of: name),
                    request: GeminiCachedContentPatchBody(expiration: .ttl(ttl))
                )
            )
            entries[key] = .active(name: name, expireDate: response.output.expireDate)
            eventHandler?(.extended(name: name, until: response.output.expireDate))
        } catch let error as GeminiCachedContentError where error == .notFound {
            entries[key] = nil
        } catch {
            // A failed extension is not fatal: keep using the resource until its current expiry,
            // and recover by recreating it once that passes.
        }
    }

    private static func resourceId(of name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }
}
