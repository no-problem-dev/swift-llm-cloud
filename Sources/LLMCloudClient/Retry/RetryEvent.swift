import Foundation
import LLMClient

// MARK: - RetryEvent

/// One retry that is about to happen: what failed, and how long the client will wait.
///
/// ``RetryRunner`` emits an event only when it has already decided to retry — after the policy
/// approved the error and before the wait begins. So a failure that exhausts the budget or is
/// not retryable produces no event, and the number of events observed is the number of retries,
/// one fewer than the number of attempts. Nothing is emitted on success.
public struct RetryEvent: Sendable {
    /// Number of the attempt that just failed, counting from 1.
    public let attempt: Int

    /// Retry budget the policy was configured with, which puts the attempt number in context.
    public let maxRetries: Int

    /// The failure that triggered the retry.
    ///
    /// Already unwrapped from ``RateLimitAwareError`` when it arrived inside one, so an observer
    /// sees the domain error rather than the transport envelope.
    public let error: LLMError

    /// Seconds the client will sleep before the next attempt, jitter included.
    public let delaySeconds: TimeInterval

    /// A short human-readable label for the failure, suitable for a log line.
    ///
    /// Distinguishes rate limiting, server errors with their status code, timeouts, and network
    /// errors; anything else collapses to a generic label, since only retryable errors reach an
    /// observer in the first place.
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

    /// Retries still left in the budget after this one, floored at 0.
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

/// Observer called once per retry, synchronously, on whichever task is running the request.
///
/// It runs before the wait, so a slow handler delays the retry it is reporting. Keep it to
/// logging or metrics.
public typealias RetryEventHandler = @Sendable (RetryEvent) -> Void

// MARK: - RetryConfiguration

/// Retry settings a client takes at construction, before it has a policy object.
///
/// This is the plain-value form callers pass to a provider client; the client turns it into a
/// live policy through ``policy``. Only the built-in exponential backoff can be described this
/// way — anything else means conforming to ``RetryPolicy`` and handing that to the retry loop
/// directly.
public struct RetryConfiguration: Sendable {
    /// Whether failures are retried at all.
    ///
    /// When false, ``policy`` resolves to ``NoRetryPolicy`` and the remaining fields are ignored.
    public let isEnabled: Bool

    /// Attempts after the first one.
    public let maxRetries: Int

    /// Wait before the first retry, in seconds, and the base the backoff doubles from.
    public let baseDelay: TimeInterval

    /// Ceiling on the computed backoff, in seconds. A wait a provider asked for can still
    /// exceed it.
    public let maxDelay: TimeInterval

    /// Retry up to 5 times with 1 to 60 second exponential backoff.
    public static let `default` = RetryConfiguration(
        isEnabled: true, maxRetries: 5, baseDelay: 1.0, maxDelay: 60.0
    )

    /// Send once and let the first failure through.
    public static let disabled = RetryConfiguration(
        isEnabled: false, maxRetries: 0, baseDelay: 0, maxDelay: 0
    )

    /// Retry up to 10 times with 0.5 to 120 second exponential backoff.
    public static let aggressive = RetryConfiguration(
        isEnabled: true, maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0
    )

    /// Retry up to 3 times with 2 to 30 second exponential backoff.
    public static let conservative = RetryConfiguration(
        isEnabled: true, maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0
    )

    /// Stores the settings verbatim, without validating them.
    ///
    /// Out-of-range values are clamped later, when ``policy`` builds the backoff, so the
    /// properties here report exactly what was passed in.
    public init(isEnabled: Bool, maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval) {
        self.isEnabled = isEnabled
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Builds a configuration with a custom budget, enabling retries only when the budget is
    /// positive.
    ///
    /// Passing 0 or a negative count yields a disabled configuration rather than an enabled one
    /// with nothing to spend.
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

    /// The live policy these settings describe.
    ///
    /// ``NoRetryPolicy`` when disabled, otherwise an ``ExponentialBackoffPolicy`` built from the
    /// stored counts — which is where out-of-range values get clamped, and where `jitterFactor`
    /// takes its 10% default since this type does not expose one. A fresh value is returned on
    /// every access.
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
