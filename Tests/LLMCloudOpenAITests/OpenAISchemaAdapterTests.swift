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
}
