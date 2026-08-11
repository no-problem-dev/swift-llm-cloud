import Foundation
import LLMClient
import LLMCloudClient

/// A tool offered to the model, in the only kind these vendors support: a function.
///
/// The parameter schema is wrapped as a `WireSchema` before encoding. Request bodies go out with a
/// snake_case key strategy, which would otherwise rename schema keywords such as
/// `additionalProperties` and leave the vendor with a schema it cannot read.
package struct OpenAICompatibleToolDef: Encodable, Sendable {
    package let type: String
    package let function: OpenAICompatibleFunctionDef

    package init(name: String, description: String, parameters: JSONSchema, strict: Bool = true) {
        self.type = "function"
        self.function = OpenAICompatibleFunctionDef(
            name: name, description: description, strict: strict, parameters: WireSchema(parameters)
        )
    }
}

/// The function half of a tool definition: what it is called, what it does, and what it takes.
package struct OpenAICompatibleFunctionDef: Encodable, Sendable {
    package let name: String
    package let description: String
    package let strict: Bool
    package let parameters: WireSchema
}

/// How free the model is to decide which tool to call.
///
/// The first three cases encode as the bare strings `auto`, `none`, and `required`; naming a
/// function encodes as an object instead, which is what forces that one tool.
package enum OpenAICompatibleToolChoice: Encodable, Sendable {
    case auto
    case none
    case required
    case function(String)

    private struct FunctionChoice: Encodable {
        let type: String
        let function: FunctionName

        struct FunctionName: Encodable {
            let name: String
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .none:
            try container.encode("none")
        case .required:
            try container.encode("required")
        case .function(let name):
            try container.encode(FunctionChoice(type: "function", function: .init(name: name)))
        }
    }
}
