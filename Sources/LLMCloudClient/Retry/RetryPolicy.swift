import Foundation
import LLMClient

// MARK: - RetryPolicy Protocol

public protocol RetryPolicy: Sendable {
    var maxRetries: Int { get }
    func shouldRetry(error: LLMError, attempt: Int) -> Bool
    func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval
}

// MARK: - ExponentialBackoffPolicy

public struct ExponentialBackoffPolicy: RetryPolicy {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitterFactor: Double

    public static let `default` = ExponentialBackoffPolicy()

    public static let aggressive = ExponentialBackoffPolicy(
        maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0, jitterFactor: 0.2
    )

    public static let conservative = ExponentialBackoffPolicy(
        maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0, jitterFactor: 0.1
    )

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

public struct NoRetryPolicy: RetryPolicy {
    public let maxRetries: Int = 0
    public static let shared = NoRetryPolicy()
    private init() {}

    public func shouldRetry(error: LLMError, attempt: Int) -> Bool { false }
    public func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval { 0 }
}

// MARK: - LLMError Extension

extension LLMError {
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
