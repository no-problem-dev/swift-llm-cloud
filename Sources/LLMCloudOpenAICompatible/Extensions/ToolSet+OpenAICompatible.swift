import Foundation
import LLMClient
import LLMTool

// MARK: - ToolSet OpenAI Format Conversion

extension ToolSet {
    /// OpenAI API 形式に変換
    public func toOpenAIFormat() -> [[String: Any]] {
        toProviderFormat(adapter: OpenAISchemaAdapter()) { tool, adaptedSchema in
            var functionDict: [String: Any] = [
                "name": tool.name,
                "description": tool.toolDescription,
                "strict": true
            ]
            if let schema = adaptedSchema {
                functionDict["parameters"] = schema
            }
            return [
                "type": "function",
                "function": functionDict
            ]
        }
    }
}

// MARK: - Tool OpenAI Format Extension

extension Tool {
    /// OpenAI API 形式に変換
    func toOpenAIFormat() -> [String: Any] {
        var functionDict: [String: Any] = [
            "name": toolName,
            "description": toolDescription,
            "strict": true
        ]

        let adapter = OpenAISchemaAdapter()
        if let schemaData = try? adapter.adapt(inputSchema).toJSONData(),
           let schemaDict = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] {
            functionDict["parameters"] = schemaDict
        }

        return [
            "type": "function",
            "function": functionDict
        ]
    }
}
