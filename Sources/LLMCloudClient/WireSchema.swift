import Foundation
import LLMClient
import StructuredDataCore
import JSONParsing

/// プロバイダーのリクエストボディに JSON Schema を埋め込むためのラッパー。
///
/// 多くのプロバイダー（OpenAI 互換 / Anthropic）はボディを snake_case で直列化するが、
/// JSON Schema のキーワード（`additionalProperties` / `minItems` / `maxLength` 等）は
/// 仕様上 camelCase 固定であり、snake_case 化すると `additional_properties` のように壊れて
/// 「`additionalProperties:false` must be set on every object」等で拒否される。
///
/// `WireSchema` は埋め込み schema を事前に `StructuredValue` へ lower して保持する。
/// swift-structured-data の `ValueEncoder` は `StructuredValue` をキー戦略変換せずそのまま
/// 通すため、親ボディの key 戦略に関係なく JSON Schema キーワードが verbatim で出力される。
///
/// 埋め込み schema フィールドは `JSONSchema` を直接持たず必ず `WireSchema` を経由させることで、
/// 「どこか 1 箇所で passthrough を忘れる」事故を型レベルで防ぐ。
public struct WireSchema: Encodable, Sendable, Equatable {
    /// 元の JSON Schema（意味的表現）。
    public let schema: JSONSchema

    public init(_ schema: JSONSchema) {
        self.schema = schema
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.lowered(schema))
    }

    /// JSONSchema を、キーワードを変換しない `StructuredValue` へ lower する。
    /// Foundation の既定キー（= Swift プロパティ名 = JSON Schema キーワード）で直列化する。
    static func lowered(_ schema: JSONSchema) throws -> StructuredValue {
        let data = try Foundation.JSONEncoder().encode(schema)
        return try JSONParser().parse(data)
    }
}
