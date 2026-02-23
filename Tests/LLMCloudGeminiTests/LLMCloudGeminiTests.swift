import Testing
@testable import LLMCloudGemini
@testable import LLMCloudClient

@Test func testGeminiSchemaAdapterInit() {
    let adapter = GeminiSchemaAdapter()
    _ = adapter  // Confirm it can be instantiated
}
