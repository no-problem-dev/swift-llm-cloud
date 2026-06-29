import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - RetryableProviderProtocol

/// リトライ可能なプロバイダーのプロトコル。
///
/// HTTP レスポンスを含むリクエスト送信機能を持ち、
/// レート制限情報の抽出とリトライ判定を可能にする。
public protocol RetryableProviderProtocol: LLMProvider {
    /// リクエストを送信し、LLM レスポンスと HTTP レスポンスのタプルを返す。
    ///
    /// - Parameter request: 送信する LLM リクエスト。
    /// - Returns: LLM レスポンスと HTTP レスポンスのタプル。
    /// - Throws: リクエストの送信に失敗した場合。
    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse)
}

// MARK: - RetryableProvider

/// リトライ機能付きの LLM プロバイダーラッパー。
///
/// 内部プロバイダーをラップし、設定されたリトライポリシーに基づいて
/// 失敗したリクエストを自動的にリトライする。
/// レート制限情報を考慮した待機時間の調整もサポートする。
public struct RetryableProvider<ExtractorType: RateLimitInfoExtractable>: LLMProvider {
    private let innerProvider: any RetryableProviderProtocol
    private let retryPolicy: any RetryPolicy
    private let eventHandler: RetryEventHandler?

    /// 新しいリトライ可能プロバイダーを作成する。
    ///
    /// - Parameters:
    ///   - provider: ラップする内部プロバイダー。
    ///   - extractorType: レート制限情報の抽出に使用する型。
    ///   - retryPolicy: リトライポリシー。デフォルトは指数バックオフ。
    ///   - eventHandler: リトライイベントのハンドラー（オプション）。
    public init(
        provider: any RetryableProviderProtocol,
        extractorType: ExtractorType.Type,
        retryPolicy: any RetryPolicy = ExponentialBackoffPolicy.default,
        eventHandler: RetryEventHandler? = nil
    ) {
        self.innerProvider = provider
        self.retryPolicy = retryPolicy
        self.eventHandler = eventHandler
    }

    public func send(_ request: LLMRequest) async throws -> LLMResponse {
        try await RetryRunner.run(policy: retryPolicy, eventHandler: eventHandler) {
            try await innerProvider.sendWithResponse(request).0
        }
    }
}

// MARK: - RateLimitAwareError

/// レート制限情報と元エラーをペアで保持するエラー型。
///
/// HTTP レスポンスからレート制限情報を抽出した際に生成される。
/// `RetryRunner` がレート制限情報を待機時間の計算に利用するために使用する。
public struct RateLimitAwareError: Error, Sendable {
    /// 元のLLMエラー。
    public let underlyingError: LLMError
    /// 抽出されたレート制限情報。
    public let rateLimitInfo: RateLimitInfo
    /// HTTPステータスコード。
    public let statusCode: Int

    /// 新しいレート制限対応エラーを作成する。
    ///
    /// - Parameters:
    ///   - underlyingError: 元の LLM エラー。
    ///   - rateLimitInfo: 抽出されたレート制限情報。
    ///   - statusCode: HTTP ステータスコード。
    public init(underlyingError: LLMError, rateLimitInfo: RateLimitInfo, statusCode: Int) {
        self.underlyingError = underlyingError
        self.rateLimitInfo = rateLimitInfo
        self.statusCode = statusCode
    }
}
