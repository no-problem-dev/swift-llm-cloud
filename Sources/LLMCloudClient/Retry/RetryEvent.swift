import Foundation
import LLMClient

// MARK: - RetryEvent

/// リトライイベント
public struct RetryEvent: Sendable {
    public let attempt: Int
    public let maxRetries: Int
    public let error: LLMError
    public let delaySeconds: TimeInterval

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

/// リトライ設定
public struct RetryConfiguration: Sendable {
    public let isEnabled: Bool
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public static let `default` = RetryConfiguration(
        isEnabled: true, maxRetries: 5, baseDelay: 1.0, maxDelay: 60.0
    )

    public static let disabled = RetryConfiguration(
        isEnabled: false, maxRetries: 0, baseDelay: 0, maxDelay: 0
    )

    public static let aggressive = RetryConfiguration(
        isEnabled: true, maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0
    )

    public static let conservative = RetryConfiguration(
        isEnabled: true, maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0
    )

    public init(isEnabled: Bool, maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval) {
        self.isEnabled = isEnabled
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

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
