import Testing
import LLMClient
import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// Pins the OpenAI schema adapter to the shared generic adapter under its OpenAI profile.
///
/// ``OpenAISchemaAdapter`` only selects the `.openAI` capability set, so the parity case catches
/// that selection being rewired rather than two implementations drifting. The cases after it are
/// what pin strict mode itself: every keyword except `enum` removed, every property listed in
/// `required`, optionality expressed by nullability, and those invariants holding at every depth.
@Suite("OpenAI schema adapter")
struct OpenAISchemaAdapterTests {
    private let input = JSONSchema(
        type: .object,
        properties: [
            "name": JSONSchema(type: .string, minLength: 2, maxLength: 10, pattern: "^[a-z]+$", format: "email"),
            "age": JSONSchema(type: .integer, minimum: 0, maximum: 120, exclusiveMinimum: 1, exclusiveMaximum: 119),
            "tags": JSONSchema(type: .array, items: JSONSchema(type: .string), minItems: 1, maxItems: 5),
            "kind": JSONSchema(type: .string, enum: ["a", "b"]),
        ],
        required: ["name"],
        additionalProperties: true
    )

    @Test("Generic(.openAI) は既存実装と一致")
    func matchesExisting() {
        let generic = GenericSchemaAdapter(capabilities: .openAI).adaptWithConstraints(input, fieldPath: "")
        let original = OpenAISchemaAdapter().adaptWithConstraints(input, fieldPath: "")
        #expect(generic.schema == original.schema)
        #expect(generic.removedConstraints.count == original.removedConstraints.count)
        for constraint in original.removedConstraints {
            #expect(generic.removedConstraints.contains(constraint))
        }
    }

    @Test("OpenAI は全制約除去・additionalProperties=false・required 全プロパティ化・enum 保持")
    func enforcesStrict() {
        let result = GenericSchemaAdapter(capabilities: .openAI).adaptWithConstraints(input, fieldPath: "")
        #expect(result.schema.additionalProperties == false)
        #expect(result.schema.required == ["age", "kind", "name", "tags"]) // sorted all props
        let props = result.schema.properties
        #expect(props?["age"]?.minimum == nil)
        #expect(props?["tags"]?.minItems == nil)
        #expect(props?["name"]?.format == nil)
        #expect(props?["kind"]?.enum == ["a", "b"])  // enum kept
    }

    @Test("optional プロパティ(required 外)は nullable 化され、required は全プロパティを含む")
    func optionalBecomesNullable() {
        let result = GenericSchemaAdapter(capabilities: .openAI).adaptWithConstraints(input, fieldPath: "")
        let props = result.schema.properties
        // name was required in the input, so it stays non-nullable.
        #expect(props?["name"]?.nullable == false)
        // age, tags, and kind were optional, so nullability is how that survives.
        #expect(props?["age"]?.nullable == true)
        #expect(props?["tags"]?.nullable == true)
        #expect(props?["kind"]?.nullable == true)
        // Every property is still listed in required — strict mode allows no other arrangement.
        #expect(result.schema.required == ["age", "kind", "name", "tags"])
    }

    @Test("strict 正規化は全 object ノードで不変条件を満たす(再帰)")
    func strictInvariantHoldsRecursively() {
        let nested = JSONSchema(
            type: .object,
            properties: [
                "user": JSONSchema(type: .object, properties: [
                    "name": JSONSchema(type: .string),
                    "address": JSONSchema(type: .object, properties: [
                        "city": JSONSchema(type: .string),
                    ], required: []),
                ], required: ["name"]),
                "items": JSONSchema(type: .array, items: JSONSchema(type: .object, properties: [
                    "id": JSONSchema(type: .integer),
                ], required: ["id"])),
                "empty": JSONSchema(type: .object, properties: [:]),
            ],
            required: ["user"]
        )
        let adapted = GenericSchemaAdapter(capabilities: .openAI).adapt(nested)
        assertStrictInvariant(adapted)
    }

    /// Recursively checks that every object node satisfies OpenAI strict mode.
    ///
    /// The three invariants are `additionalProperties: false`, a non-nil `properties` map, and a
    /// `required` array listing every key of that map. Array element schemas are walked too, so an
    /// object nested inside an array is covered rather than skipped.
    private func assertStrictInvariant(_ schema: JSONSchema, path: String = "<root>") {
        if schema.type == .object {
            #expect(schema.additionalProperties == false, "\(path): additionalProperties must be false")
            #expect(schema.properties != nil, "\(path): properties must be present")
            let keys = Set(schema.properties?.keys.map { $0 } ?? [])
            #expect(Set(schema.required ?? []) == keys, "\(path): required must list all properties")
            for (key, value) in schema.properties ?? [:] {
                assertStrictInvariant(value, path: "\(path).\(key)")
            }
        }
        if let items = schema.items?.value {
            assertStrictInvariant(items, path: "\(path)[]")
        }
    }
}
