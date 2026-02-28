import Foundation

/// OpenAI 互換ツール定義
package struct OpenAICompatibleToolDef: Encodable, @unchecked Sendable {
    package let type: String
    package let function: OpenAICompatibleFunctionDef

    package init(dict: [String: Any]) {
        self.type = dict["type"] as? String ?? "function"
        if let funcDict = dict["function"] as? [String: Any] {
            self.function = OpenAICompatibleFunctionDef(dict: funcDict)
        } else {
            self.function = OpenAICompatibleFunctionDef(dict: [:])
        }
    }
}

/// OpenAI 互換関数定義
package struct OpenAICompatibleFunctionDef: Encodable, @unchecked Sendable {
    package let name: String
    package let description: String
    package let strict: Bool
    package let parameters: [String: Any]

    package init(dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        self.strict = dict["strict"] as? Bool ?? true
        self.parameters = dict["parameters"] as? [String: Any] ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case name, description, strict, parameters
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(strict, forKey: .strict)
        let paramsData = try JSONSerialization.data(withJSONObject: parameters)
        let paramsJSON = try JSONDecoder().decode(OpenAICompatibleJSONValue.self, from: paramsData)
        try container.encode(paramsJSON, forKey: .parameters)
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
