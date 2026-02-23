import Foundation
import LLMClient
import LLMTool

// MARK: - ToolSet Anthropic Format Conversion

extension ToolSet {
    /// Anthropic API 形式に変換
    public func toAnthropicFormat() -> [[String: Any]] {
        toProviderFormat(adapter: AnthropicSchemaAdapter()) { tool, adaptedSchema in
            var result: [String: Any] = [
                "name": tool.name,
                "description": tool.toolDescription
            ]
            if let schema = adaptedSchema {
                result["input_schema"] = schema
            }
            return result
        }
    }
}

// MARK: - Tool Anthropic Format Extension

extension Tool {
    /// Anthropic API 形式に変換
    func toAnthropicFormat() -> [String: Any] {
        var result: [String: Any] = [
            "name": toolName,
            "description": toolDescription
        ]

        let adapter = AnthropicSchemaAdapter()
        if let schemaData = try? adapter.adapt(inputSchema).toJSONData(),
           let schemaDict = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] {
            result["input_schema"] = schemaDict
        }

        return result
    }
}
