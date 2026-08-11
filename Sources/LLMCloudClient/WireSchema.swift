import Foundation
import LLMClient
import StructuredDataCore
import JSONParsing

/// Carries a JSON Schema into a request body without letting the body's key strategy rename its
/// keywords.
///
/// Most providers, OpenAI-compatible and Anthropic alike, serialize their request bodies in
/// snake_case. JSON Schema keywords are camelCase by specification, so a body-wide conversion
/// turns `additionalProperties` into `additional_properties` and the provider rejects the
/// request with errors such as "additionalProperties:false must be set on every object" — the
/// keyword it is looking for is no longer there.
///
/// This type lowers the schema to a `StructuredValue` at encode time. The `ValueEncoder` in
/// swift-structured-data passes a `StructuredValue` through without applying a key strategy, so
/// the keywords land on the wire verbatim no matter what the enclosing body does.
///
/// Schema-bearing fields on request bodies hold this type rather than a bare `JSONSchema`, which
/// makes the passthrough impossible to forget at one call site out of many.
public struct WireSchema: Encodable, Sendable, Equatable {
    /// The schema as declared, before lowering.
    public let schema: JSONSchema

    public init(_ schema: JSONSchema) {
        self.schema = schema
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.lowered(schema))
    }

    /// Lowers a schema to a value whose keys are already the final keywords.
    ///
    /// Encodes through Foundation with its default key coding, where the Swift property names
    /// are the JSON Schema keywords, then parses the bytes straight back into a
    /// `StructuredValue`.
    static func lowered(_ schema: JSONSchema) throws -> StructuredValue {
        let data = try Foundation.JSONEncoder().encode(schema)
        return try JSONParser().parse(data)
    }
}
