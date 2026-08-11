import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One provider's rate-limit header names and the way it encodes reset times.
///
/// Providers publish the same handful of facts under different names and in different formats,
/// so each contributes a table like this and the parsing lives in one place. A nil header name
/// means the provider does not send that fact, and the corresponding field comes back nil.
package struct RateLimitHeaderExtraction: Sendable {
    /// How a reset header states when the window refills.
    package enum ResetFormat: Sendable {
        /// An absolute RFC 3339 timestamp, converted to seconds from now. Anthropic.
        ///
        /// Floored at 0, so clock skew or a response that sat in a queue cannot produce a
        /// negative wait.
        case rfc3339
        /// A duration with a unit suffix, such as `500ms`, `1s`, `6m`, or `1h`. OpenAI-compatible
        /// vendors. A bare number is read as seconds.
        case durationSuffix
        /// A plain number of seconds.
        case seconds
    }

    /// Header carrying an explicit wait instruction, conventionally `Retry-After`.
    package var retryAfter: String?

    /// Header carrying requests left in the current window.
    package var remainingRequests: String?

    /// Header carrying when the request window refills, read per the reset format below.
    package var requestsReset: String?

    /// Header carrying tokens left in the current window.
    package var remainingTokens: String?

    /// Header carrying when the token window refills, read per the reset format below.
    package var tokensReset: String?

    /// Encoding shared by both reset headers.
    package var resetFormat: ResetFormat

    package init(
        retryAfter: String? = "retry-after",
        remainingRequests: String? = nil,
        requestsReset: String? = nil,
        remainingTokens: String? = nil,
        tokensReset: String? = nil,
        resetFormat: ResetFormat = .seconds
    ) {
        self.retryAfter = retryAfter
        self.remainingRequests = remainingRequests
        self.requestsReset = requestsReset
        self.remainingTokens = remainingTokens
        self.tokensReset = tokensReset
        self.resetFormat = resetFormat
    }

    /// Reads the configured headers off a response, filling in nil for each one that is absent
    /// or does not parse.
    ///
    /// A header present but malformed is treated exactly like a missing one — extraction never
    /// throws and never guesses. `Retry-After` is read only in its delta-seconds form; the
    /// HTTP-date form the specification also allows parses to nil.
    package func extract(from response: HTTPURLResponse) -> RateLimitInfo {
        func value(_ name: String?) -> String? { name.flatMap { response.value(forHTTPHeaderField: $0) } }
        return build(value)
    }

    /// Reads the same headers out of the plain dictionary an API contract's error decoding
    /// receives, matching names case-insensitively.
    ///
    /// This is the path that actually feeds retries, since rate-limit values reach the retry
    /// loop through the contract rather than through a raw response. Parsing is shared with the
    /// `HTTPURLResponse` overload.
    package func extract(from headers: [String: String]) -> RateLimitInfo {
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, b in b })
        func value(_ name: String?) -> String? { name.flatMap { lowered[$0.lowercased()] } }
        return build(value)
    }

    private func build(_ value: (String?) -> String?) -> RateLimitInfo {
        RateLimitInfo(
            retryAfter: value(retryAfter).flatMap { Double($0) },
            remainingRequests: value(remainingRequests).flatMap { Int($0) },
            requestsResetIn: value(requestsReset).flatMap(parseReset),
            remainingTokens: value(remainingTokens).flatMap { Int($0) },
            tokensResetIn: value(tokensReset).flatMap(parseReset)
        )
    }

    private func parseReset(_ raw: String) -> TimeInterval? {
        switch resetFormat {
        case .seconds:
            return Double(raw.trimmingCharacters(in: .whitespaces))
        case .rfc3339:
            return RateLimitHeaderExtraction.parseRFC3339(raw)
        case .durationSuffix:
            return RateLimitHeaderExtraction.parseDurationSuffix(raw)
        }
    }

    private static func parseRFC3339(_ value: String) -> TimeInterval? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    /// Reads a single-unit duration into seconds.
    ///
    /// The `ms` suffix is tested before `s` so milliseconds are not read as seconds. A string
    /// with no recognized suffix is read as a bare number of seconds; anything else yields nil.
    private static func parseDurationSuffix(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("ms") { return Double(trimmed.dropLast(2)).map { $0 / 1000 } }
        if trimmed.hasSuffix("s") { return Double(trimmed.dropLast(1)) }
        if trimmed.hasSuffix("m") { return Double(trimmed.dropLast(1)).map { $0 * 60 } }
        if trimmed.hasSuffix("h") { return Double(trimmed.dropLast(1)).map { $0 * 3600 } }
        return Double(trimmed)
    }

    /// Anthropic: separate request and token budgets under `anthropic-ratelimit-*`, with resets
    /// as absolute RFC 3339 timestamps.
    package static let anthropic = RateLimitHeaderExtraction(
        retryAfter: "retry-after",
        remainingRequests: "anthropic-ratelimit-requests-remaining",
        requestsReset: "anthropic-ratelimit-requests-reset",
        remainingTokens: "anthropic-ratelimit-tokens-remaining",
        tokensReset: "anthropic-ratelimit-tokens-reset",
        resetFormat: .rfc3339
    )

    /// OpenAI and the vendors that mirror its API: separate request and token budgets under
    /// `x-ratelimit-*`, with resets as single-unit duration strings.
    package static let openAICompatible = RateLimitHeaderExtraction(
        retryAfter: "retry-after",
        remainingRequests: "x-ratelimit-remaining-requests",
        requestsReset: "x-ratelimit-reset-requests",
        remainingTokens: "x-ratelimit-remaining-tokens",
        tokensReset: "x-ratelimit-reset-tokens",
        resetFormat: .durationSuffix
    )

    /// Gemini: `retry-after` and nothing else, so remaining counts and resets are always nil and
    /// backoff is the only signal available between failures.
    package static let gemini = RateLimitHeaderExtraction(retryAfter: "retry-after")
}
