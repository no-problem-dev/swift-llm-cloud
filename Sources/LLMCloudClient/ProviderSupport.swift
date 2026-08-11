import APIClient
import Foundation
import LLMClient

/// Supplies a fixed API key as the auth token, for the providers that authenticate with one.
///
/// The token is held for the lifetime of the client and never refreshed, which is what every
/// provider here needs: none of them issue short-lived credentials.
package struct StaticTokenProvider: AuthTokenProvider {
    package let token: String
    package init(token: String) { self.token = token }
    package func fetchToken() async throws -> String? { token }
}

/// Joins the caller's system prompt with the schema constraints the provider could not enforce.
///
/// The constraint block comes from schema adaptation: keywords the provider's structured-output
/// endpoint rejects are stripped from the wire schema and restated here as instructions, so the
/// model is still told about a `pattern` or a `minimum` the decoder can no longer enforce.
/// Rendered after the caller's text, separated by a blank line. Returns nil only when there is
/// neither.
package func composeSystemPrompt(base: String?, constraints: SystemPrompt?) -> String? {
    switch (base, constraints) {
    case (let base?, let constraints?): return "\(base)\n\n\(constraints.render())"
    case (let base?, nil): return base
    case (nil, let constraints?): return constraints.render()
    case (nil, nil): return nil
    }
}

package extension URL {
    /// The parent URL with its trailing slash removed, safe to use as an endpoint base.
    ///
    /// `deletingLastPathComponent()` yields a URL that ends in a slash, such as `…/v1beta/`.
    /// Some Foundation versions then join that with a path that starts with a slash and produce
    /// `…/v1beta//models/…`, which providers do not route. Normalizing here keeps every base URL
    /// slash-free at the end so the join has exactly one separator.
    var deletingLastPathComponentAsBase: URL {
        let parent = deletingLastPathComponent()
        guard parent.absoluteString.hasSuffix("/") else { return parent }
        return URL(string: String(parent.absoluteString.dropLast())) ?? parent
    }
}

/// Translates a transport failure into the domain error the retry loop and callers understand.
///
/// Providers call this only for failures their API contract did not already decode: an
/// `httpError` that reaches here keeps its status code, so `LLMError.isRetryable` can still
/// tell a 5xx worth retrying from a 4xx that will fail again. A 429 normally arrives as a
/// ``RateLimitAwareError`` from the contract instead and never passes through here.
///
/// A 401 and a 403 both land on `LLMError.unauthorized`. That case already means "the API key
/// is missing, wrong, or not allowed to reach this model", which is both halves of the
/// distinction `APIError` draws, and the remedy at this layer is the same either way: the
/// credential or the plan behind it has to change, and resending is pointless. Every provider
/// contract in this package already collapses the two the same way in its own `decodeError`.
///
/// `TransportError.invalidResponse` arrives inside ``APIError/networkError(_:)`` and is
/// reported as a network failure, which is where it has always arrived from — `APIError` had a
/// separate `invalidResponse` case that was never constructed.
package func mapAPIErrorToLLMError(_ error: APIError) -> LLMError {
    switch error {
    case .unauthorized, .forbidden: return .unauthorized
    case .networkError(let underlying): return .networkError(underlying)
    case .decodingError(let underlying): return .decodingFailed(underlying)
    case .invalidURL: return .invalidRequest("Invalid URL")
    case .conflictingAuthHeader(let name):
        return .invalidRequest("Header \(name) collides with the credential the contract resolved")
    case .httpError(let statusCode, _): return .serverError(statusCode, "HTTP error")
    }
}
