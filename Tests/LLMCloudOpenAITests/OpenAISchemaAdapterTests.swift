import Testing
import LLMClient
import LLMCloudClient
@testable import LLMCloudOpenAICompatible

/// GenericSchemaAdapter(.openAI) が既存 OpenAISchemaAdapter と完全一致することを検証する。
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
        // required だった name は nullable にならない。
        #expect(props?["name"]?.nullable == false)
        // optional だった age / tags / kind は nullable 化。
        #expect(props?["age"]?.nullable == true)
        #expect(props?["tags"]?.nullable == true)
        #expect(props?["kind"]?.nullable == true)
        // それでも全プロパティが required に含まれる（OpenAI strict 標準）。
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

    /// 全 object ノードが ①additionalProperties:false ②properties 非 nil ③required=全キー を満たす。
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
