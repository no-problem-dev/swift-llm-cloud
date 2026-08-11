import Foundation

/// The envelope these vendors wrap a failure in.
package struct OpenAICompatibleErrorResponse: Decodable, Sendable {
    package let error: OpenAICompatibleError
}

/// The vendor's own account of what went wrong.
///
/// Only the message can be relied on. The other three are filled in inconsistently across vendors,
/// and a body that does not parse at all is not fatal — the status code still decides which error
/// the caller sees, just without the vendor's wording.
package struct OpenAICompatibleError: Decodable, Sendable {
    package let message: String
    package let type: String?
    package let param: String?
    package let code: String?
}
