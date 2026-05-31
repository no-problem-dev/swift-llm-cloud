import Testing
import LLMClient
import LLMCloudClient
@testable import LLMCloudAnthropic

/// GenericSchemaAdapter(.anthropic) が既存 AnthropicSchemaAdapter と完全一致することを
/// 検証する（適合後スキーマは等価、除去制約は同一集合）。リグレッション防止のゴールデン。
@Suite("Anthropic schema adapter")
struct AnthropicSchemaAdapterTests {
    private let input = JSONSchema(
        type: .object,
        properties: [
            "name": JSONSchema(type: .string, minLength: 2, maxLength: 10, pattern: "^[a-z]+$", format: "email"),
            "age": JSONSchema(type: .integer, minimum: 0, maximum: 120, exclusiveMinimum: 1, exclusiveMaximum: 119),
            "shortTags": JSONSchema(type: .array, items: JSONSchema(type: .string), minItems: 1, maxItems: 5),
            "longTags": JSONSchema(type: .array, items: JSONSchema(type: .string), minItems: 3),
            "kind": JSONSchema(type: .string, enum: ["a", "b"]),
        ],
        required: ["name"],
        additionalProperties: true
    )

    @Test("Generic(.anthropic) は既存実装と一致")
    func matchesExisting() {
        let generic = GenericSchemaAdapter(capabilities: .anthropic).adaptWithConstraints(input, fieldPath: "")
        let original = AnthropicSchemaAdapter().adaptWithConstraints(input, fieldPath: "")
        #expect(generic.schema == original.schema)
        #expect(generic.removedConstraints.count == original.removedConstraints.count)
        for constraint in original.removedConstraints {
            #expect(generic.removedConstraints.contains(constraint))
        }
    }

    @Test("Anthropic は minItems<=1 を保持し >1 を除去・pattern/format を保持")
    func keepsExpectedConstraints() {
        let result = GenericSchemaAdapter(capabilities: .anthropic).adaptWithConstraints(input, fieldPath: "")
        let props = result.schema.properties
        #expect(props?["shortTags"]?.minItems == 1)        // <=1 kept
        #expect(props?["longTags"]?.minItems == nil)       // >1 removed
        #expect(props?["name"]?.pattern == "^[a-z]+$")     // pattern kept
        #expect(props?["name"]?.format == "email")         // format kept
        #expect(props?["age"]?.minimum == nil)             // numeric removed
        #expect(result.schema.additionalProperties == true) // passthrough
    }
}
