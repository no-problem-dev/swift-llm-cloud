import Foundation
import LLMClient

// MARK: - RetryPolicy Protocol

/// Decides whether a failed request is sent again, and how long to wait first.
///
/// A policy sees the domain error, the number of the attempt that just failed, and whatever
/// rate-limit values the transport recovered from the failing response, so it can honor a
/// wait the provider asked for instead of a wait it computed itself. ``RetryRunner`` drives
/// the loop; a policy holds no state across attempts.
public protocol RetryPolicy: Sendable {
    var maxRetries: Int { get }

    /// Reports whether the failure that just happened should be retried.
    ///
    /// - Parameters:
    ///   - error: The failure the attempt produced.
    ///   - attempt: Number of the attempt that just failed, counting from 1.
    func shouldRetry(error: LLMError, attempt: Int) -> Bool

    /// Returns how many seconds to wait before the next attempt.
    ///
    /// - Parameters:
    ///   - attempt: Number of the attempt that just failed, counting from 1.
    ///   - error: The failure the attempt produced.
    ///   - rateLimitInfo: Rate-limit values read off the failing response, when the provider
    ///     sent any. ``RetryRunner`` passes the most recent set it has seen, which may come
    ///     from an earlier attempt than this one.
    func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval
}

// MARK: - ExponentialBackoffPolicy

/// Retry policy that doubles the wait after each failed attempt and spreads retries with jitter.
///
/// The computed wait for the retry after attempt *n* is `baseDelay * 2^(n - 1)`, capped at
/// `maxDelay`, plus jitter. Jitter keeps a fleet of clients that failed together from coming
/// back at the same instant.
///
/// A wait the provider asked for wins over the computed one — see
/// ``delay(for:error:rateLimitInfo:)``.
public struct ExponentialBackoffPolicy: RetryPolicy {
    public let maxRetries: Int

    /// Wait before the first retry, in seconds, and the base the backoff doubles from.
    public let baseDelay: TimeInterval

    /// Ceiling on the computed backoff, in seconds.
    ///
    /// It does not bound a wait the provider asked for: a `Retry-After` of 300 seconds is
    /// honored in full even when `maxDelay` is 60.
    public let maxDelay: TimeInterval

    /// Share of the wait that may be added as jitter, from 0 to 1.
    ///
    /// Jitter only lengthens a wait, so 0.1 means "up to 10% longer", never shorter.
    public let jitterFactor: Double

    /// Policy used when a caller does not supply one: 5 retries, 1 s base, 60 s ceiling, 10% jitter.
    public static let `default` = ExponentialBackoffPolicy()

    /// Retries more and waits less: 10 retries, 0.5 s base, 120 s ceiling, 20% jitter.
    public static let aggressive = ExponentialBackoffPolicy(
        maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0, jitterFactor: 0.2
    )

    /// Retries less and waits longer: 3 retries, 2 s base, 30 s ceiling, 10% jitter.
    public static let conservative = ExponentialBackoffPolicy(
        maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0, jitterFactor: 0.1
    )

    /// Creates a policy, clamping every argument into a range that yields a usable backoff.
    ///
    /// Negative values for `maxRetries` and `baseDelay` are raised to 0, `jitterFactor` is
    /// clamped to 0...1, and `maxDelay` is raised to `baseDelay` when it would otherwise be
    /// smaller — so the stored values can never describe a backoff that waits a negative time
    /// or whose ceiling sits below its first step. The clamped values are what the properties
    /// report back, which may differ from what was passed in.
    ///
    /// - Parameters:
    ///   - maxRetries: Attempts after the first one. 0 means the request is sent exactly once.
    ///   - baseDelay: Wait before the first retry, in seconds.
    ///   - maxDelay: Ceiling on the computed backoff, in seconds.
    ///   - jitterFactor: Share of the wait that may be added as jitter.
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

    /// Retries while the budget holds and the error is one that resending can fix.
    ///
    /// Retryability comes from `LLMError.isRetryable`, so the error itself decides; this policy
    /// only enforces the attempt budget on top of it.
    public func shouldRetry(error: LLMError, attempt: Int) -> Bool {
        guard attempt <= maxRetries else { return false }
        return error.isRetryable
    }

    /// Returns the wait the provider asked for when the response carried one, and an
    /// exponential backoff otherwise.
    ///
    /// A `suggestedWaitTime` greater than zero on `rateLimitInfo` takes precedence over the
    /// computed backoff and is not capped by `maxDelay`: when a provider says "come back in
    /// 90 seconds", that is the number honored. That value is itself the first non-nil of
    /// `Retry-After`, the request-window reset, and the token-window reset — see
    /// ``RateLimitInfo/suggestedWaitTime``.
    ///
    /// Otherwise the wait is `baseDelay * 2^(attempt - 1)`, capped at `maxDelay`.
    ///
    /// Jitter is applied to whichever value won, and is one-sided rather than the usual ±: the
    /// result is `delay + delay * jitterFactor * random(0...1)`, so a jittered wait is always
    /// at least the unjittered one. A wait is never shortened below what the provider asked for.
    public func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval {
        if let suggestedWait = rateLimitInfo?.suggestedWaitTime, suggestedWait > 0 {
            return addJitter(to: suggestedWait)
        }
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)
        return addJitter(to: cappedDelay)
    }

    /// Lengthens a wait by a random share of itself, never shortening it.
    private func addJitter(to delay: TimeInterval) -> TimeInterval {
        let jitter = delay * jitterFactor * Double.random(in: 0...1)
        return delay + jitter
    }
}

// MARK: - NoRetryPolicy

/// Retry policy that sends the request once and lets the first failure through.
///
/// ``RetryRunner`` makes `maxRetries + 1` attempts, so a zero budget means one attempt and the
/// error reaches the caller unchanged. This is what ``RetryConfiguration/disabled`` resolves to.
public struct NoRetryPolicy: RetryPolicy {
    public let maxRetries: Int = 0
    public static let shared = NoRetryPolicy()
    private init() {}

    public func shouldRetry(error: LLMError, attempt: Int) -> Bool { false }
    public func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval { 0 }
}

// MARK: - LLMError Extension

extension LLMError {
    /// Whether sending the same request again could plausibly succeed.
    ///
    /// Retryable: `rateLimitExceeded`, `serverError` with a status in 500...599, `timeout`, and
    /// `networkError`. Everything else is terminal, including a `serverError` whose status falls
    /// outside 5xx — a 4xx says the request itself is wrong, and resending it byte for byte gets
    /// the same answer. So `unauthorized`, `invalidRequest`, `modelNotFound`, `emptyResponse`,
    /// `invalidEncoding`, `decodingFailed`, `modelNotSupported`, `structuredOutputNotSupported`,
    /// `contentBlocked`, `maxTokensReached`, `mediaNotSupported`, and `unknown` all report false.
    ///
    /// The switch lists every case instead of falling back to `default`, so a new case added to
    /// `LLMError` breaks the build here and forces someone to classify it, rather than silently
    /// inheriting "do not retry".
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
