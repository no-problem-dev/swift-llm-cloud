import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - RateLimitInfo

public struct RateLimitInfo: Sendable {
    public let retryAfter: TimeInterval?
    public let remainingRequests: Int?
    public let requestsResetIn: TimeInterval?
    public let remainingTokens: Int?
    public let tokensResetIn: TimeInterval?

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

    public var suggestedWaitTime: TimeInterval? {
        retryAfter ?? requestsResetIn ?? tokensResetIn
    }
}

// MARK: - RateLimitInfoExtractable Protocol

public protocol RateLimitInfoExtractable {
    static func extractRateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo
}
