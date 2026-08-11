import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// Converts the tools into Anthropic tool definitions.
    ///
    /// Each schema is adapted to what Anthropic enforces and kept as a typed schema all the way
    /// to serialization, never passing through an untyped dictionary, so JSON Schema keywords
    /// reach the wire spelled the way the specification requires.
    func toAnthropicToolDefs() -> [AnthropicToolDef] {
        toProviderFormat(adapter: AnthropicSchemaAdapter()) { tool, adaptedSchema in
            AnthropicToolDef(name: tool.toolName, description: tool.toolDescription, inputSchema: adaptedSchema)
        }
    }
}
