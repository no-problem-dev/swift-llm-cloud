import Foundation
import LLMClient
import LLMCloudClient

/// Rewrites a JSON schema into the OpenAPI subset Gemini accepts.
///
/// Gemini keeps `minItems`, `maxItems`, `minimum`, and `maximum`, and of the string formats only
/// `date-time`, `date`, and `time`. It rejects the exclusive numeric bounds, `minLength` and
/// `maxLength`, `pattern`, other formats, and `additionalProperties`, so those are stripped.
/// Optional properties stay optional, unlike OpenAI's strict mode which requires every property.
///
/// Constraints that get stripped are not silently lost: ``adaptWithConstraints(_:fieldPath:)``
/// returns them so the caller can restate them in the system prompt. All of this is configuration
/// on ``GenericSchemaAdapter``; this type only selects the Gemini profile.
struct GeminiSchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .gemini)
    init() {}
    func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
