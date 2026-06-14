import Foundation
import LLMClient
import StructuredDataCore
import JSONParsing

/// OpenAI 互換ボディは snake_case で直列化されるが、その中に埋め込む JSON Schema の
/// キーワード（`additionalProperties` / `minItems` / `maxLength` 等）は JSON Schema 仕様上
/// camelCase でなければならない。snake_case 化されると Groq 等が
/// 「`additionalProperties:false` must be set on every object」と拒否する。
///
/// swift-structured-data の ValueEncoder は `StructuredValue` をキー変換せずそのまま通すため、
/// スキーマを事前に `StructuredValue` へ lower してから埋め込むことで snake_case 化を回避する。
enum JSONSchemaPassthrough {
    private static let parser = JSONParser()

    /// JSONSchema を、キーワードを変換しない `StructuredValue` へ変換する。
    /// Foundation の既定キー（= Swift プロパティ名 = JSON Schema キーワード）で直列化する。
    static func structuredValue(_ schema: JSONSchema) throws -> StructuredValue {
        let data = try Foundation.JSONEncoder().encode(schema)
        return try parser.parse(data)
    }
}
