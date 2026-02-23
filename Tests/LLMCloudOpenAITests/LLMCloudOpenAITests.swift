import Testing
@testable import LLMCloudOpenAI
@testable import LLMCloudClient

@Test func testOpenAISchemaAdapterInit() {
    let adapter = OpenAISchemaAdapter()
    _ = adapter  // Confirm it can be instantiated
}
