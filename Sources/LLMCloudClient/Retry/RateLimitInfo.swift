import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - RateLimitInfo

/// APIレート制限の情報
///
/// HTTPレスポンスヘッダーから抽出されたレート制限に関する情報を保持します。
/// リトライ待機時間の算出に使用されます。
public struct RateLimitInfo: Sendable {
    /// サーバーが指定したリトライ待機時間（秒）。
    public let retryAfter: TimeInterval?
    /// 残りリクエスト数。
    public let remainingRequests: Int?
    /// リクエスト制限がリセットされるまでの時間（秒）。
    public let requestsResetIn: TimeInterval?
    /// 残りトークン数。
    public let remainingTokens: Int?
    /// トークン制限がリセットされるまでの時間（秒）。
    public let tokensResetIn: TimeInterval?

    /// 情報なしの空インスタンス。
    public static let empty = RateLimitInfo(
        retryAfter: nil, remainingRequests: nil, requestsResetIn: nil,
        remainingTokens: nil, tokensResetIn: nil
    )

    /// 新しいレート制限情報を作成します。
    ///
    /// - Parameters:
    ///   - retryAfter: サーバーが指定したリトライ待機時間（秒）。
    ///   - remainingRequests: 残りリクエスト数。
    ///   - requestsResetIn: リクエスト制限がリセットされるまでの時間（秒）。
    ///   - remainingTokens: 残りトークン数。
    ///   - tokensResetIn: トークン制限がリセットされるまでの時間（秒）。
    public init(
        retryAfter: TimeInterval?,
        remainingRequests: Int?,
        requestsResetIn: TimeInterval?,
        remainingTokens: Int?,
        tokensResetIn: TimeInterval?
    ) {
        self.retryAfter = retryAfter
        self.remainingRequests = remainingRequests
        self.requestsResetIn = requestsResetIn
        self.remainingTokens = remainingTokens
        self.tokensResetIn = tokensResetIn
    }

    /// 推奨される待機時間（秒）。
    ///
    /// `retryAfter`、`requestsResetIn`、`tokensResetIn` の順で最初に利用可能な値を返します。
    public var suggestedWaitTime: TimeInterval? {
        retryAfter ?? requestsResetIn ?? tokensResetIn
    }
}

// MARK: - RateLimitInfoExtractable Protocol

/// HTTPレスポンスからレート制限情報を抽出するプロトコル
///
/// プロバイダー固有のレスポンスヘッダーからレート制限情報を解析する機能を提供します。
public protocol RateLimitInfoExtractable {
    /// HTTPレスポンスからレート制限情報を抽出します。
    ///
    /// - Parameter response: レート制限ヘッダーを含むHTTPレスポンス。
    /// - Returns: 抽出されたレート制限情報。
    static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo
}
