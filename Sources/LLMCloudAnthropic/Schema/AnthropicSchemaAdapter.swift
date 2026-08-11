import Foundation
import LLMClient
import LLMCloudClient

/// Trims a JSON Schema to what Anthropic's constrained decoding can enforce.
///
/// The behaviour lives in the shared `.anthropic` capability set. Anthropic keeps more than
/// OpenAI does: `pattern`, every `format`, and `additionalProperties` as written, and `minItems`
/// when it is 0 or 1. Numeric ranges, string lengths, and `maxItems` are removed, and larger
/// `minItems` values with them. Removed constraints are reported back to the caller so they can
/// be restated in the prompt instead of vanishing.
struct AnthropicSchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .anthropic)
    init() {}
    func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
