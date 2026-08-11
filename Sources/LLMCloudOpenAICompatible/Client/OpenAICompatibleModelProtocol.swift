import LLMCloudClient
import LLMClient

/// What a vendor's model enum has to expose for the shared engine to send requests for it.
///
/// The id is the string that goes into the request as-is, so it has to be spelled the way that one
/// vendor spells it.
public protocol OpenAICompatibleModelProtocol: Sendable, Equatable {
    var id: String { get }

    func toLLMModel() -> LLMModel
}
