import Testing
import LLMClient
import LLMCloudClient
@testable import LLMCloudGemini

/// Pins the Gemini schema adapter to the shared generic adapter under its Gemini capability set.
///
/// ``GeminiSchemaAdapter`` only selects that capability set, so what this catches is the selection
/// being rewired to a different profile; it will not notice a change inside the shared adapter,
/// since both sides move together. Both halves of the result are compared: the adapted schema, and
/// the removed-constraint list that the caller restates in the system prompt so a keyword Gemini
/// rejects is not silently dropped from the requirements.
@Suite("Gemini schema adapter")
struct GeminiSchemaAdapterTests {
    private let input = JSONSchema(
        type: .object,
        properties: [
            "name": JSONSchema(type: .string, minLength: 2, maxLength: 10, pattern: "^[a-z]+$", format: "email"),
            "when": JSONSchema(type: .string, format: "date-time"),
            "age": JSONSchema(type: .integer, minimum: 0, maximum: 120, exclusiveMinimum: 1, exclusiveMaximum: 119),
            "tags": JSONSchema(type: .array, items: JSONSchema(type: .string), minItems: 1, maxItems: 5),
        ],
        required: ["name"],
        additionalProperties: true
    )

    @Test("Generic(.gemini) は既存実装と一致")
    func matchesExisting() {
        let generic = GenericSchemaAdapter(capabilities: .gemini).adaptWithConstraints(input, fieldPath: "")
        let original = GeminiSchemaAdapter().adaptWithConstraints(input, fieldPath: "")
        #expect(generic.schema == original.schema)
        #expect(generic.removedConstraints.count == original.removedConstraints.count)
        for constraint in original.removedConstraints {
            #expect(generic.removedConstraints.contains(constraint))
        }
    }

    @Test("Gemini は minItems/maxItems/numeric/whitelist format を保持し pattern/length/additionalProperties を除去")
    func keepsExpectedConstraints() {
        let result = GenericSchemaAdapter(capabilities: .gemini).adaptWithConstraints(input, fieldPath: "")
        let props = result.schema.properties
        #expect(props?["tags"]?.minItems == 1)
        #expect(props?["tags"]?.maxItems == 5)
        #expect(props?["age"]?.minimum == 0)
        #expect(props?["when"]?.format == "date-time")  // whitelisted
        #expect(props?["name"]?.format == nil)          // email not whitelisted → removed
        #expect(props?["name"]?.pattern == nil)
        #expect(result.schema.additionalProperties == nil)
    }
}
