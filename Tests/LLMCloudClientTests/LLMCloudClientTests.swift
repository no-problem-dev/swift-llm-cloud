import Testing
import LLMClient
@testable import LLMCloudClient

@Test func testClaudeModelId() {
    #expect(ClaudeModel.opus.id == "claude-opus-4-8")
    #expect(ClaudeModel.opus4_7.id == "claude-opus-4-7")
    #expect(ClaudeModel.opus4_6.id == "claude-opus-4-6")
    #expect(ClaudeModel.sonnet.id == "claude-sonnet-4-6")
    #expect(ClaudeModel.haiku.id == "claude-haiku-4-5")
}

@Test func testGPTModelId() {
    #expect(GPTModel.gpt5_5.id == "gpt-5.5")
    #expect(GPTModel.gpt5_4.id == "gpt-5.4")
    #expect(GPTModel.gpt5_4Mini.id == "gpt-5.4-mini")
    #expect(GPTModel.gpt4o.id == "gpt-4o")
    #expect(GPTModel.o3.id == "o3")
    #expect(GPTModel.o4Mini.id == "o4-mini")
}

@Test func testGeminiModelId() {
    #expect(GeminiModel.flash25.id == "gemini-2.5-flash")
    #expect(GeminiModel.pro25.id == "gemini-2.5-pro")
    #expect(GeminiModel.flashLite25.id == "gemini-2.5-flash-lite")
    #expect(GeminiModel.flash35.id == "gemini-3.5-flash")
    #expect(GeminiModel.flash3Preview.id == "gemini-3-flash-preview")
    #expect(GeminiModel.pro31Preview.id == "gemini-3.1-pro-preview")
    #expect(GeminiModel.flashLite31.id == "gemini-3.1-flash-lite")
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
