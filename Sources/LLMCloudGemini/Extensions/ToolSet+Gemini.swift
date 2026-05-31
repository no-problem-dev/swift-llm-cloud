import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// Gemini API の functionDeclarations 配列に変換。スキーマは JSONSchema のまま保持し、
    /// 直列化は contract codec に委ねる（[String: Any] を介さない）。
    func toGeminiFunctionDeclarations() -> [GeminiFunctionDeclaration] {
        toProviderFormat(adapter: GeminiSchemaAdapter()) { tool, adaptedSchema in
            GeminiFunctionDeclaration(name: tool.toolName, description: tool.toolDescription, parameters: adaptedSchema)
        }
    }
}
