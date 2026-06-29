import Foundation
import LLMClient

// MARK: - RetryPolicy Protocol

/// リトライポリシーを定義するプロトコル。
///
/// エラー発生時のリトライ判定とリトライ間隔の計算ロジックを提供する。
/// レート制限情報を考慮した待機時間の算出もサポートする。
public protocol RetryPolicy: Sendable {
    /// 最大リトライ回数。
    var maxRetries: Int { get }
    /// 指定されたエラーに対してリトライすべきかを判定する。
    ///
    /// - Parameters:
    ///   - error: 発生したエラー。
    ///   - attempt: 現在の試行回数。
    func shouldRetry(error: LLMError, attempt: Int) -> Bool
    /// 指定された試行回数に対するリトライ待機時間を計算する。
    ///
    /// - Parameters:
    ///   - attempt: 現在の試行回数。
    ///   - error: 発生したエラー。
    ///   - rateLimitInfo: レート制限情報（利用可能な場合）。
    /// - Returns: リトライまでの待機時間（秒）。
    func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval
}

// MARK: - ExponentialBackoffPolicy

/// 指数バックオフによるリトライポリシー
///
/// リトライごとに待機時間を指数関数的に増加させる。
/// ジッター（ランダムな揺らぎ）を加えることで、同時リトライの集中を防ぐ。
public struct ExponentialBackoffPolicy: RetryPolicy {
    public let maxRetries: Int
    /// 基本待機時間（秒）。
    public let baseDelay: TimeInterval
    /// 最大待機時間（秒）。
    public let maxDelay: TimeInterval
    /// ジッター係数（0.0〜1.0）。
    public let jitterFactor: Double

    /// デフォルトのリトライポリシー。
    public static let `default` = ExponentialBackoffPolicy()

    /// アグレッシブなリトライポリシー（リトライ回数多め、待機時間短め）。
    public static let aggressive = ExponentialBackoffPolicy(
        maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0, jitterFactor: 0.2
    )

    /// コンサバティブなリトライポリシー（リトライ回数少なめ、待機時間長め）。
    public static let conservative = ExponentialBackoffPolicy(
        maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0, jitterFactor: 0.1
    )

    /// 新しい指数バックオフポリシーを作成する。
    ///
    /// - Parameters:
    ///   - maxRetries: 最大リトライ回数。デフォルトは 5。
    ///   - baseDelay: 基本待機時間（秒）。デフォルトは 1.0。
    ///   - maxDelay: 最大待機時間（秒）。デフォルトは 60.0。
    ///   - jitterFactor: ジッター係数。デフォルトは 0.1。
    public init(
        maxRetries: Int = 5,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        jitterFactor: Double = 0.1
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(baseDelay, maxDelay)
        self.jitterFactor = min(1.0, max(0, jitterFactor))
    }

    public func shouldRetry(error: LLMError, attempt: Int) -> Bool {
        guard attempt <= maxRetries else { return false }
        return error.isRetryable
    }

    public func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval {
        if let suggestedWait = rateLimitInfo?.suggestedWaitTime, suggestedWait > 0 {
            return addJitter(to: suggestedWait)
        }
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)
        return addJitter(to: cappedDelay)
    }

    private func addJitter(to delay: TimeInterval) -> TimeInterval {
        let jitter = delay * jitterFactor * Double.random(in: 0...1)
        return delay + jitter
    }
}

// MARK: - NoRetryPolicy

/// リトライを行わないポリシー。
///
/// エラー発生時にリトライせず、即座に失敗させる。
public struct NoRetryPolicy: RetryPolicy {
    public let maxRetries: Int = 0
    /// 共有インスタンス。
    public static let shared = NoRetryPolicy()
    private init() {}

    public func shouldRetry(error: LLMError, attempt: Int) -> Bool { false }
    public func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval { 0 }
}

// MARK: - LLMError Extension

extension LLMError {
    /// このエラーがリトライ可能かどうか。
    ///
    /// レート制限超過、サーバーエラー（5xx）、タイムアウト、ネットワークエラーの場合に `true` を返す。
    public var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded:
            return true
        case .serverError(let code, _):
            return (500...599).contains(code)
        case .timeout:
            return true
        case .networkError:
            return true
        case .unauthorized, .invalidRequest, .modelNotFound,
             .emptyResponse, .invalidEncoding, .decodingFailed,
             .modelNotSupported, .structuredOutputNotSupported,
             .contentBlocked, .maxTokensReached, .mediaNotSupported,
             .unknown:
            return false
        }
    }
}
