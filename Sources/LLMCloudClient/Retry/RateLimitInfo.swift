import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - RateLimitInfo

/// What a provider's rate-limit headers said on one response.
///
/// Providers meter requests and tokens as two separate budgets and report them under different
/// header names, so every field is optional and most providers populate only some of them.
/// Anthropic sends the full set under `anthropic-ratelimit-*`, OpenAI-compatible vendors under
/// `x-ratelimit-*`, and Gemini sends nothing beyond `Retry-After`. See
/// `RateLimitHeaderExtraction` for the per-provider mapping.
public struct RateLimitInfo: Sendable {
    /// Seconds the provider asked the client to wait, from `Retry-After`.
    public let retryAfter: TimeInterval?

    /// Requests left in the current request-count window, not a token figure.
    public let remainingRequests: Int?

    /// Seconds until the request-count window refills.
    ///
    /// Providers publish this as an absolute timestamp or a duration string depending on the
    /// vendor; it is normalized to seconds from now on extraction.
    public let requestsResetIn: TimeInterval?

    /// Tokens left in the current token window, counting prompt plus completion tokens against
    /// the provider's per-window budget.
    public let remainingTokens: Int?

    /// Seconds until the token window refills.
    public let tokensResetIn: TimeInterval?

    /// A response that carried no rate-limit headers at all.
    public static let empty = RateLimitInfo(
        retryAfter: nil, remainingRequests: nil, requestsResetIn: nil,
        remainingTokens: nil, tokensResetIn: nil
    )

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

    /// How long the provider implies the client should wait, in seconds.
    ///
    /// The first non-nil of ``retryAfter``, ``requestsResetIn``, and ``tokensResetIn``, in that
    /// order: an explicit instruction beats a window that is about to refill. Nil when the
    /// response carried none of the three, which is the signal for a policy to fall back to its
    /// own backoff. ``ExponentialBackoffPolicy`` treats a positive value here as authoritative
    /// and does not cap it.
    public var suggestedWaitTime: TimeInterval? {
        retryAfter ?? requestsResetIn ?? tokensResetIn
    }
}

// MARK: - RateLimitInfoExtractable Protocol

/// Reads one provider's rate-limit headers off a response.
///
/// Conformers are caseless enums, one per provider, that forward to a
/// `RateLimitHeaderExtraction` describing that provider's header names and reset encoding.
public protocol RateLimitInfoExtractable {
    /// Reads whatever rate-limit headers the response carries.
    ///
    /// Returns an all-nil ``RateLimitInfo`` rather than nil when none are present, so callers do
    /// not have to distinguish "no headers" from "headers that parsed to nothing".
    ///
    /// - Parameter response: The response to read, successful or not.
    static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo
}
