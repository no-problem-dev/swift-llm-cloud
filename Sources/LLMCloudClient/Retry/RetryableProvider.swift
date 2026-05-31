import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - RetryableProviderProtocol

/// リトライ可能なプロバイダーのプロトコル
///
/// HTTPレスポンスを含むリクエスト送信機能を提供し、
/// レート制限情報の抽出とリトライ判定を可能にします。
public protocol RetryableProviderProtocol: LLMProvider {
    /// リクエストを送信し、レスポンスとHTTPレスポンスの両方を返します。
    ///
    /// - Parameter request: 送信するLLMリクエスト。
    /// - Returns: LLMレスポンスとHTTPレスポンスのタプル。
    /// - Throws: リクエストの送信に失敗した場合。
    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse)
}

// MARK: - RetryableProvider

/// リトライ機能付きのLLMプロバイダーラッパー
///
/// 内部プロバイダーをラップし、設定されたリトライポリシーに基づいて
/// 失敗したリクエストを自動的にリトライします。
/// レート制限情報を考慮した待機時間の調整もサポートします。
public struct RetryableProvider<ExtractorType: RateLimitInfoExtractable>: LLMProvider {
    private let innerProvider: any RetryableProviderProtocol
    private let retryPolicy: any RetryPolicy
    private let eventHandler: RetryEventHandler?

    /// 新しいリトライ可能プロバイダーを作成します。
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

/// レート制限情報を含むエラー
///
/// HTTPレスポンスからレート制限情報を抽出した際に、
/// 元のエラーとレート制限情報をペアで保持します。
public struct RateLimitAwareError: Error, Sendable {
    /// 元のLLMエラー。
    public let underlyingError: LLMError
    /// 抽出されたレート制限情報。
    public let rateLimitInfo: RateLimitInfo
    /// HTTPステータスコード。
    public let statusCode: Int

    /// 新しいレート制限対応エラーを作成します。
    ///
    /// - Parameters:
    ///   - underlyingError: 元のLLMエラー。
    ///   - rateLimitInfo: 抽出されたレート制限情報。
    ///   - statusCode: HTTPステータスコード。
    public init(underlyingError: LLMError, rateLimitInfo: RateLimitInfo, statusCode: Int) {
        self.underlyingError = underlyingError
        self.rateLimitInfo = rateLimitInfo
        self.statusCode = statusCode
    }
}
