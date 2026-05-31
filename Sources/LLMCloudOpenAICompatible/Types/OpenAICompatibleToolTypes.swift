import Foundation
import LLMClient

/// OpenAI 互換ツール定義。スキーマは JSONSchema のまま保持し直列化は contract codec に委ねる。
package struct OpenAICompatibleToolDef: Encodable, Sendable {
    package let type: String
    package let function: OpenAICompatibleFunctionDef

    package init(name: String, description: String, parameters: JSONSchema, strict: Bool = true) {
        self.type = "function"
        self.function = OpenAICompatibleFunctionDef(
            name: name, description: description, strict: strict, parameters: parameters
        )
    }
}

/// OpenAI 互換関数定義
package struct OpenAICompatibleFunctionDef: Encodable, Sendable {
    package let name: String
    package let description: String
    package let strict: Bool
    package let parameters: JSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description, strict, parameters
    }
}

/// OpenAI 互換ツール選択
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
