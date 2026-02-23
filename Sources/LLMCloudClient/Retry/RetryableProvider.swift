import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - RetryableProviderProtocol

public protocol RetryableProviderProtocol: LLMProvider {
    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse)
}

// MARK: - RetryableProvider

public struct RetryableProvider<ExtractorType: RateLimitInfoExtractable>: LLMProvider {
    private let innerProvider: any RetryableProviderProtocol
    private let retryPolicy: any RetryPolicy
    private let eventHandler: RetryEventHandler?

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
        var lastError: LLMError?
        var lastRateLimitInfo: RateLimitInfo?

        let maxAttempts = retryPolicy.maxRetries + 1

        for attempt in 1...maxAttempts {
            do {
                let (response, httpResponse) = try await innerProvider.sendWithResponse(request)
                _ = ExtractorType.extractRateLimitInfo(from: httpResponse)
                return response

            } catch let rateLimitError as RateLimitAwareError {
                lastRateLimitInfo = rateLimitError.rateLimitInfo
                lastError = rateLimitError.underlyingError

                guard retryPolicy.shouldRetry(error: rateLimitError.underlyingError, attempt: attempt) else {
                    throw rateLimitError.underlyingError
                }

                guard attempt < maxAttempts else {
                    throw rateLimitError.underlyingError
                }

                let delay = retryPolicy.delay(
                    for: attempt, error: rateLimitError.underlyingError, rateLimitInfo: lastRateLimitInfo
                )

                if let handler = eventHandler {
                    let event = RetryEvent(
                        attempt: attempt, maxRetries: retryPolicy.maxRetries,
                        error: rateLimitError.underlyingError, delaySeconds: delay
                    )
                    handler(event)
                }

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch let error as LLMError {
                lastError = error

                guard retryPolicy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }

                guard attempt < maxAttempts else {
                    throw error
                }

                let delay = retryPolicy.delay(
                    for: attempt, error: error, rateLimitInfo: lastRateLimitInfo
                )

                if let handler = eventHandler {
                    let event = RetryEvent(
                        attempt: attempt, maxRetries: retryPolicy.maxRetries,
                        error: error, delaySeconds: delay
                    )
                    handler(event)
                }

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? LLMError.unknown(NSError(domain: "RetryableProvider", code: -1))
    }
}

// MARK: - RateLimitAwareError

public struct RateLimitAwareError: Error, Sendable {
    public let underlyingError: LLMError
    public let rateLimitInfo: RateLimitInfo
    public let statusCode: Int

    public init(underlyingError: LLMError, rateLimitInfo: RateLimitInfo, statusCode: Int) {
        self.underlyingError = underlyingError
        self.rateLimitInfo = rateLimitInfo
        self.statusCode = statusCode
    }
}
