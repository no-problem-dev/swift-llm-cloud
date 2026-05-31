import StructuredDataCore

/// JSON 値の汎用 Codable 型（OpenAI 互換プロバイダー共通）。
///
/// 独自 enum を廃し、swift-structured-data の ``StructuredValue`` に統一した。
/// ツール引数・スキーマのパススルー（decode → encode）に用いる。
package typealias OpenAICompatibleJSONValue = StructuredValue
