import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// Converts the tool set into wire definitions, reducing each schema to what strict mode allows.
    ///
    /// Schemas stay typed the whole way to the encoder instead of passing through an untyped
    /// dictionary, so nothing is dropped or reordered on the way out.
    func toOpenAIToolDefs() -> [OpenAICompatibleToolDef] {
        toProviderFormat(adapter: OpenAISchemaAdapter()) { tool, adaptedSchema in
            OpenAICompatibleToolDef(name: tool.toolName, description: tool.toolDescription, parameters: adaptedSchema)
        }
    }
}
