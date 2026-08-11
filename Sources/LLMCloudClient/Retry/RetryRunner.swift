import LLMClient
import Foundation

/// The single retry loop every provider in this package funnels through.
///
/// It understands two failure shapes and nothing else: `LLMError`, and ``RateLimitAwareError``,
/// which is what a provider's API contract raises when the failing response carried rate-limit
/// headers. Because the contract has already parsed those headers into a ``RateLimitInfo``, the
/// loop never needs the raw HTTP response — which is why the same implementation serves plain
/// sends and agent turns alike. Streaming does not go through it: a stream that has already
/// delivered tokens cannot be restarted transparently.
///
/// Any error that is neither of those two shapes escapes the loop uncaught and is never
/// retried, whatever a policy would have said about it.
public enum RetryRunner {
    /// Runs an operation, retrying it while the policy allows.
    ///
    /// Makes at most `policy.maxRetries + 1` attempts. After each failure the error is unwrapped
    /// to its `LLMError` form and offered to the policy; when the policy declines, or the budget
    /// is spent, that error is thrown. Otherwise a ``RetryEvent`` is emitted and the task sleeps
    /// for the wait the policy computed.
    ///
    /// Rate-limit values are sticky: the most recent ``RateLimitInfo`` seen is remembered and
    /// handed to the policy on later attempts too, so a wait a provider asked for on a 429 still
    /// shapes the backoff after a subsequent failure that carried no headers of its own.
    ///
    /// - Parameters:
    ///   - policy: Decides retryability and waits.
    ///   - eventHandler: Called once per retry, before the wait.
    ///   - operation: The work to attempt. It is re-run from scratch each time, so it must be
    ///     safe to repeat — which for a chat completion means the provider is billed for every
    ///     attempt, not only the one that succeeds.
    /// - Throws: The last `LLMError` when retries run out, `CancellationError` if the task is
    ///   cancelled during a wait, or anything the operation threw that is neither an `LLMError`
    ///   nor a ``RateLimitAwareError``.
    public static func run<R>(
        policy: any RetryPolicy,
        eventHandler: RetryEventHandler?,
        operation: () async throws -> R
    ) async throws -> R {
        var lastRateLimitInfo: RateLimitInfo?
        let maxAttempts = policy.maxRetries + 1

        for attempt in 1...maxAttempts {
            let llmError: LLMError
            do {
                return try await operation()
            } catch let rateLimitError as RateLimitAwareError {
                lastRateLimitInfo = rateLimitError.rateLimitInfo
                llmError = rateLimitError.underlyingError
            } catch let error as LLMError {
                llmError = error
            }

            guard policy.shouldRetry(error: llmError, attempt: attempt), attempt < maxAttempts else {
                throw llmError
            }

            let delay = policy.delay(for: attempt, error: llmError, rateLimitInfo: lastRateLimitInfo)
            eventHandler?(RetryEvent(
                attempt: attempt, maxRetries: policy.maxRetries, error: llmError, delaySeconds: delay
            ))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        throw LLMError.unknown(NSError(domain: "RetryRunner", code: -1))
    }
}
