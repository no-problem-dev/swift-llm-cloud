import Foundation
import LLMClient

// MARK: - RetryEvent

/// リトライ試行ごとに発行されるイベント。
///
/// `RetryEventHandler` に渡され、リトライの監視・ログ記録に使用する。
public struct RetryEvent: Sendable {
    /// 現在の試行回数（1 始まり）。
    public let attempt: Int
    /// 最大リトライ回数。
    public let maxRetries: Int
    /// 発生したエラー。
    public let error: LLMError
    /// 次のリトライまでの待機時間（秒）。
    public let delaySeconds: TimeInterval

    /// エラー種別を人間向けに説明した文字列。
    public var reason: String {
        switch error {
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError(let code, _):
            return "Server error (\(code))"
        case .timeout:
            return "Request timeout"
        case .networkError:
            return "Network error"
        default:
            return "Retryable error"
        }
    }

    /// 残りリトライ可能回数。
    public var remainingRetries: Int {
        max(0, maxRetries - attempt)
    }

    public init(attempt: Int, maxRetries: Int, error: LLMError, delaySeconds: TimeInterval) {
        self.attempt = attempt
        self.maxRetries = maxRetries
        self.error = error
        self.delaySeconds = delaySeconds
    }
}

// MARK: - RetryEventHandler

public typealias RetryEventHandler = @Sendable (RetryEvent) -> Void

// MARK: - RetryConfiguration

/// リトライの有効化・回数・待機時間を宣言する設定型。
///
/// プロバイダー初期化時に渡す。`policy` でビルトインの `ExponentialBackoffPolicy` を生成する。
/// カスタムポリシーが必要な場合は `RetryPolicy` プロトコルを直接実装する。
public struct RetryConfiguration: Sendable {
    /// リトライを有効にするか。
    public let isEnabled: Bool
    /// 最大リトライ回数。
    public let maxRetries: Int
    /// 基本待機時間（秒）。指数バックオフの基点。
    public let baseDelay: TimeInterval
    /// 最大待機時間（秒）。バックオフがこれを超えないようにクランプされる。
    public let maxDelay: TimeInterval

    /// デフォルト設定（最大 5 回、1〜60 秒の指数バックオフ）。
    public static let `default` = RetryConfiguration(
        isEnabled: true, maxRetries: 5, baseDelay: 1.0, maxDelay: 60.0
    )

    /// リトライ無効。エラーを即座に throw する。
    public static let disabled = RetryConfiguration(
        isEnabled: false, maxRetries: 0, baseDelay: 0, maxDelay: 0
    )

    /// アグレッシブ設定（最大 10 回、0.5〜120 秒）。
    public static let aggressive = RetryConfiguration(
        isEnabled: true, maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0
    )

    /// コンサバティブ設定（最大 3 回、2〜30 秒）。
    public static let conservative = RetryConfiguration(
        isEnabled: true, maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0
    )

    public init(isEnabled: Bool, maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval) {
        self.isEnabled = isEnabled
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// カスタム回数・待機時間で設定を生成する。
    public static func custom(
        maxRetries: Int,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0
    ) -> RetryConfiguration {
        RetryConfiguration(
            isEnabled: maxRetries > 0,
            maxRetries: maxRetries,
            baseDelay: baseDelay,
            maxDelay: maxDelay
        )
    }

    public var policy: any RetryPolicy {
        guard isEnabled else {
            return NoRetryPolicy.shared
        }
        return ExponentialBackoffPolicy(
            maxRetries: maxRetries,
            baseDelay: baseDelay,
            maxDelay: maxDelay
        )
    }
}
