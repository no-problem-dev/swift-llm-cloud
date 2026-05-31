import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// OpenAI 互換のツール定義配列に変換。スキーマは JSONSchema のまま保持し、
    /// 直列化は contract codec に委ねる（[String: Any] を介さない）。
    func toOpenAIToolDefs() -> [OpenAICompatibleToolDef] {
        toProviderFormat(adapter: OpenAISchemaAdapter()) { tool, adaptedSchema in
            OpenAICompatibleToolDef(name: tool.toolName, description: tool.toolDescription, parameters: adaptedSchema)
        }
    }
}
