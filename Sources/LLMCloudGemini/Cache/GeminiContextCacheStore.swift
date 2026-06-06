import APIClient
import Foundation
import LLMClient
import LLMCloudClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Cache Events

/// 明示キャッシュのライフサイクルイベント（観測用）
public enum GeminiCacheEvent: Sendable {
    /// 新しいキャッシュリソースを作成した
    case created(name: String, tokenCount: Int?)
    /// 既存のキャッシュリソースを再利用した
    case reused(name: String)
    /// 期限を延長した
    case extended(name: String, until: Date?)
    /// キャッシュを使わず inline 送信にフォールバックした（恒久）
    case fallbackInline(reason: String)
    /// 失効したキャッシュを再作成して回復した
    case recovered(name: String)
    /// キャッシュリソースを削除した（ストレージ課金停止）
    case deleted(name: String)
}

public typealias GeminiCacheEventHandler = @Sendable (GeminiCacheEvent) -> Void

// MARK: - GeminiContextCacheStore

/// `cachedContents` リソースのライフサイクル管理
///
/// 安定プレフィックス（model + systemInstruction + tools + toolConfig）の
/// content hash を identity として:
/// - **冪等作成**: 同一プレフィックスへの並行 resolve は 1 つの作成に合流する
/// - **期限管理**: 残量が閾値未満なら PATCH で延長（ttl は「今から」の相対）。
///   失効済みとみなせる場合は再作成する
/// - **恒久フォールバック**: 最小トークン未満（400）は記憶して以後 inline を返す
/// - **解放**: `release()` で作成済みリソースを全削除しストレージ課金を止める
///
/// resolve は決して throw しない: キャッシュはあくまで最適化であり、
/// 失敗したら inline 送信で動作を継続する（ただしイベントで可視化する）。
actor GeminiContextCacheStore {
    private let apiClient: APIClientImpl
    private let eventHandler: GeminiCacheEventHandler?

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<GeminiPromptContext, Never>] = [:]

    private enum Entry {
        case active(name: String, expireDate: Date?)
        case inlineOnly(reason: String)
    }

    /// 失効の安全マージン。サーバー側はローカル時計より早く失効しうる
    private static let expiryMargin: TimeInterval = 60
    /// 残量がこの秒数を切ったら PATCH で延長する
    private static let extensionThreshold: TimeInterval = 300

    init(apiClient: APIClientImpl, eventHandler: GeminiCacheEventHandler?) {
        self.apiClient = apiClient
        self.eventHandler = eventHandler
    }

    // MARK: - Resolve

    /// 安定プレフィックスをプロンプト文脈に解決する
    ///
    /// キャッシュ可能なら `.cached`、不能なら `.inline` を返す。
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
                // 失効済みとみなして作り直す
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

    /// 失効が観測されたキャッシュを無効化する（generate 経路の 403/404 から呼ばれる）
    func invalidate(prefix: GeminiStablePrefix) {
        if case .active = entries[prefix.contentHash] {
            entries[prefix.contentHash] = nil
        }
    }

    /// 作成済みリソースを全削除する（セッション終了時）
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
                // 失効済み等で消せなくても TTL で消えるため黙認してよいが、観測はする
                eventHandler?(.fallbackInline(reason: "delete failed for \(name): \(error)"))
            }
        }
    }

    // MARK: - Private

    /// 同一 key の並行 resolve を 1 つの操作に合流させる（actor reentrancy 対策）
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
            // 最小トークン未満は恒久条件: 記憶して以後この prefix では作成を試みない
            if case .belowMinimumTokenCount = error {
                entries[key] = .inlineOnly(reason: "\(error)")
            }
            eventHandler?(.fallbackInline(reason: "\(error)"))
            return prefix.inlineContext
        } catch {
            // 一時障害（レート制限・ネットワーク等）: 記憶せず今回だけ inline
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
            // 延長失敗は致命的でない: 現在の期限まで使い続け、失効したら再作成で回復する
        }
    }

    private static func resourceId(of name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }
}
