import Testing
import LLMClient
import LLMCloudClient
@testable import LLMCloudAnthropic

/// Pins the Anthropic schema adapter to the shared generic adapter under its Anthropic profile.
///
/// Both halves of the result are compared: the adapted schema, and the exact set of removed
/// constraints, which the caller restates in the prompt so a dropped keyword does not silently
/// become an unenforced requirement. ``AnthropicSchemaAdapter`` only selects the `.anthropic`
/// capability set, so what this catches is that selection being rewired; the sibling cases below
/// are what actually pin Anthropic's rules, such as keeping `pattern` and a `minItems` of 0 or 1.
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
