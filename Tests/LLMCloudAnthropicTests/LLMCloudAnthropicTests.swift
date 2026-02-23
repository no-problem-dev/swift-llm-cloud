import Testing
@testable import LLMCloudAnthropic
@testable import LLMCloudClient

@Test func testAnthropicSchemaAdapterInit() {
    let adapter = AnthropicSchemaAdapter()
    _ = adapter  // Confirm it can be instantiated
}
