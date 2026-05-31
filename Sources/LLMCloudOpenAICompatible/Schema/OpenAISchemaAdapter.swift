import Foundation
import LLMClient
import LLMCloudClient

/// OpenAI Structured Outputs(strict mode)用のスキーマ適合。挙動は ``GenericSchemaAdapter``
/// の `.openAI` 設定に集約（enum のみ保持・additionalProperties=false 強制・object の
/// required を全プロパティ化・他の数値/長さ/配列/pattern/format 制約を全除去）。
///
/// 2025-05 の "improvements" 告知に反し、2026-05 時点の公式仕様でも上記制約は strict mode で
/// 非サポートのため、全除去が正しい。
package struct OpenAISchemaAdapter: ProviderSchemaAdapter {
    private let base = GenericSchemaAdapter(capabilities: .openAI)
    package init() {}
    package func adapt(_ schema: JSONSchema) -> JSONSchema { base.adapt(schema) }
    package func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        base.adaptWithConstraints(schema, fieldPath: fieldPath)
    }
}
