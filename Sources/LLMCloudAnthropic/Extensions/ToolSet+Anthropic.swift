import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// Anthropic API のツール定義配列に変換。スキーマは JSONSchema のまま保持し、
    /// 直列化は contract codec に委ねる（[String: Any] を介さない）。
    func toAnthropicToolDefs() -> [AnthropicToolDef] {
        toProviderFormat(adapter: AnthropicSchemaAdapter()) { tool, adaptedSchema in
            AnthropicToolDef(name: tool.toolName, description: tool.toolDescription, inputSchema: adaptedSchema)
        }
    }
}
