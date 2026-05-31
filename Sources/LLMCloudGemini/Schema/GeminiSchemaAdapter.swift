import Foundation
import LLMClient
import LLMCloudClient

/// Gemini API 用のスキーマ適合。挙動は ``GenericSchemaAdapter`` の `.gemini` 設定に集約
/// （minItems/maxItems/minimum/maximum/whitelist format を保持・exclusive/length/pattern/
/// additionalProperties を除去）。
struct GeminiSchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .gemini)
    init() {}
    func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
