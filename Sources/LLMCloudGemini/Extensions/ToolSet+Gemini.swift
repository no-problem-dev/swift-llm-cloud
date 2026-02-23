import Foundation
import LLMClient
import LLMTool

// MARK: - ToolSet Gemini Format Conversion

extension ToolSet {
    /// Gemini API 形式に変換
    public func toGeminiFormat() -> [[String: Any]] {
        toProviderFormat(adapter: GeminiSchemaAdapter()) { tool, adaptedSchema in
            var result: [String: Any] = [
                "name": tool.name,
                "description": tool.toolDescription
            ]
            if let schema = adaptedSchema {
                result["parameters"] = schema
            }
            return result
        }
    }
}

// MARK: - Tool Gemini Format Extension

extension Tool {
    /// Gemini API 形式に変換
    func toGeminiFormat() -> [String: Any] {
        var result: [String: Any] = [
            "name": toolName,
            "description": toolDescription
        ]

        let adapter = GeminiSchemaAdapter()
        if let schemaData = try? adapter.adapt(inputSchema).toJSONData(),
           let schemaDict = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] {
            result["parameters"] = schemaDict
        }

        return result
    }
}
