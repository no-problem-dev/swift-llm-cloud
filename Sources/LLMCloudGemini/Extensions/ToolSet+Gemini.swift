import Foundation
import LLMClient
import LLMTool

extension ToolSet {
    /// Converts the tools into Gemini function declarations, adapting each schema on the way.
    ///
    /// Parameters stay typed as a schema all the way to the contract codec rather than being
    /// flattened into an untyped dictionary, so the keywords Gemini rejects are removed by the
    /// adapter rather than by ad hoc serialization.
    func toGeminiFunctionDeclarations() -> [GeminiFunctionDeclaration] {
        toProviderFormat(adapter: GeminiSchemaAdapter()) { tool, adaptedSchema in
            GeminiFunctionDeclaration(name: tool.toolName, description: tool.toolDescription, parameters: adaptedSchema)
        }
    }
}
