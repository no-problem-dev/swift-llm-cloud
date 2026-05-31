import Foundation
import LLMClient
import LLMCloudClient

/// Anthropic API 用のスキーマ適合。挙動は ``GenericSchemaAdapter`` の `.anthropic`
/// 設定に集約（minItems<=1 のみ保持・pattern/format/additionalProperties 保持・
/// 数値/長さ/maxItems を除去）。
struct AnthropicSchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .anthropic)
    init() {}
    func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
