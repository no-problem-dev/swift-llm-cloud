import Foundation
import LLMClient
import LLMCloudClient

/// Reduces a schema to what OpenAI structured outputs accept in strict mode.
///
/// Strict mode is narrow, and the reduction follows it exactly: every object gets
/// `additionalProperties: false`, every property is listed in `required` — an optional property is
/// expressed by making it nullable instead — and the keywords strict mode does not support are
/// removed outright: numeric ranges, string lengths, array counts, `pattern`, and `format`.
/// Enumerations are the one constraint that survives. The rules themselves live in
/// ``GenericSchemaAdapter`` under its OpenAI capability set; this type only selects them.
///
/// Removing a keyword does not silently discard the requirement: the caller receives the list of
/// what was dropped and folds it back into the system prompt as instructions.
///
/// Every vendor on this engine gets the same reduction, because it happens while the request is
/// being built rather than per vendor. OpenAI announced wider keyword support in May 2025, but the
/// published strict-mode specification still lists these keywords as unsupported, so removing all
/// of them remains correct.
package struct OpenAISchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .openAI)
    package init() {}
    package func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    package func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
