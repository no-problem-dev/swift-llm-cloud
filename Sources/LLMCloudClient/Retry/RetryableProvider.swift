import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient

// MARK: - RetryableProviderProtocol

/// A provider that surfaces the raw HTTP response next to the decoded one.
///
/// The Anthropic, OpenAI-compatible, and Gemini providers all conform, each rebuilding an
/// `HTTPURLResponse` from the status and headers the API client reports.
public protocol RetryableProviderProtocol: LLMProvider {
    /// Sends a request and returns the decoded response together with the HTTP response it
    /// arrived in.
    ///
    /// The HTTP response is offered so a caller can read rate-limit headers off a *successful*
    /// exchange. No call site in this package does: retries read rate-limit values off failures
    /// instead, which arrive as ``RateLimitAwareError`` thrown by the API contract's error
    /// decoding, so every current caller discards the second tuple element.
    ///
    /// - Throws: ``RateLimitAwareError`` when the provider's contract decoded rate-limit headers
    ///   from a failing response, and `LLMError` otherwise.
    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse)
}

// MARK: - RetryableProvider

/// Wraps a provider so failed non-streaming sends are retried under a policy.
///
/// Clients install this around their base provider only when retrying is enabled; otherwise the
/// base provider is used directly. It covers the plain send and nothing else: agent turns call
/// ``RetryRunner`` themselves, and streaming is not retried at all.
///
/// When a send fails, the wait comes from the policy, and any rate-limit values ride along on a
/// ``RateLimitAwareError`` raised by the provider's contract. The `ExtractorType` parameter takes
/// no part in that: it pins a type at the call site and is never invoked.
public struct RetryableProvider<ExtractorType: RateLimitInfoExtractable>: LLMProvider {
    private let innerProvider: any RetryableProviderProtocol
    private let retryPolicy: any RetryPolicy
    private let eventHandler: RetryEventHandler?

    /// Wraps a provider in a retry loop.
    ///
    /// - Parameters:
    ///   - provider: The provider that performs the actual send.
    ///   - extractorType: Binds the generic parameter to the provider's rate-limit extractor.
    ///     It is not stored and not called; extraction happens in the provider's contract.
    ///   - retryPolicy: Decides retryability and waits. Defaults to exponential backoff.
    ///   - eventHandler: Called once per retry, just before the wait begins.
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

/// A failure that carries the rate-limit headers of the response it came from.
///
/// Each provider's API contract builds one of these in its error decoding, so the headers
/// survive the trip from the HTTP layer to the retry loop without ``RetryRunner`` needing the
/// raw response. The runner unwraps it, retries on ``underlyingError``, and hands
/// ``rateLimitInfo`` to the policy so a provider-supplied wait can beat the computed backoff.
///
/// Callers that do not run inside a retry loop are expected to unwrap it too, since it is not an
/// `LLMError` and will not match a `catch` written for one.
public struct RateLimitAwareError: Error, Sendable {
    /// The domain error the response actually represents, most often rate limiting.
    public let underlyingError: LLMError

    /// Rate-limit values read from the failing response.
    ///
    /// Every field may be nil when the provider sent no such headers, so this being present does
    /// not mean it is informative.
    public let rateLimitInfo: RateLimitInfo

    /// HTTP status of the failing response, kept for logging.
    ///
    /// Retry decisions are made from ``underlyingError``, not from this.
    public let statusCode: Int

    public init(underlyingError: LLMError, rateLimitInfo: RateLimitInfo, statusCode: Int) {
        self.underlyingError = underlyingError
        self.rateLimitInfo = rateLimitInfo
        self.statusCode = statusCode
    }
}
