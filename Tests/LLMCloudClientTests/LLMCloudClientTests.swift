import Testing
@testable import LLMCloudClient

@Test func testClaudeModelId() {
    #expect(ClaudeModel.sonnet.id == "claude-sonnet-4-5")
    #expect(ClaudeModel.opus.id == "claude-opus-4-5")
    #expect(ClaudeModel.haiku.id == "claude-haiku-4-5")
}

@Test func testGPTModelId() {
    #expect(GPTModel.gpt4o.id == "gpt-4o")
    #expect(GPTModel.gpt4oMini.id == "gpt-4o-mini")
    #expect(GPTModel.o3.id == "o3")
}

@Test func testGeminiModelId() {
    #expect(GeminiModel.flash25.id == "gemini-2.5-flash")
    #expect(GeminiModel.pro25.id == "gemini-2.5-pro")
    #expect(GeminiModel.flash3.id == "gemini-3-flash-preview")
}

@Test func testRetryConfigurationDefault() {
    let config = RetryConfiguration.default
    #expect(config.isEnabled == true)
    #expect(config.maxRetries == 5)
}

@Test func testRetryConfigurationDisabled() {
    let config = RetryConfiguration.disabled
    #expect(config.isEnabled == false)
    #expect(config.maxRetries == 0)
}
