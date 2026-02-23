English | [日本語](README.md)

# LLMCloud

A multi-provider LLM cloud client Swift package

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **Multi-Provider** - Use Anthropic Claude, OpenAI GPT, and Google Gemini through a unified API
- **Unified Interface** - Common protocol-based design across providers
- **Streaming** - Real-time output via AsyncThrowingStream for all providers
- **Function Calling** - Tool invocation support across all providers
- **Structured Output** - Type-safe responses based on JSON Schema

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", .upToNextMajor(from: "1.0.0"))
]
```

### Module Structure

Import only the modules you need:

| Module | Purpose |
|--------|---------|
| `LLMCloud` | Umbrella (re-exports all providers) |
| `LLMCloudClient` | Shared provider infrastructure |
| `LLMCloudAnthropic` | Anthropic Claude provider |
| `LLMCloudOpenAI` | OpenAI GPT provider |
| `LLMCloudGemini` | Google Gemini provider |

## Quick Start

### Anthropic Claude

```swift
import LLMCloudAnthropic

let anthropic = AnthropicProvider(apiKey: "your-api-key")
for try await chunk in anthropic.stream(messages: [
    .user("Explain concurrency in Swift 6")
], model: "claude-sonnet-4-20250514") {
    print(chunk.text, terminator: "")
}
```

### OpenAI GPT

```swift
import LLMCloudOpenAI

let openai = OpenAIProvider(apiKey: "your-api-key")
for try await chunk in openai.stream(messages: [
    .user("What are the benefits of functional programming?")
], model: "gpt-4o") {
    print(chunk.text, terminator: "")
}
```

### Google Gemini

```swift
import LLMCloudGemini

let gemini = GeminiProvider(apiKey: "your-api-key")
for try await chunk in gemini.stream(messages: [
    .user("What are SwiftUI best practices?")
], model: "gemini-2.0-flash") {
    print(chunk.text, terminator: "")
}
```

## Documentation

See the DocC documentation for detailed guides and API reference.

| Guide | Description |
|-------|-------------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) | Full public API |

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.1.0) - LLM client abstraction

## License

MIT License - See [LICENSE](LICENSE) for details

## Links

- [Full Documentation](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/)
- [Report Issues](https://github.com/no-problem-dev/swift-llm-cloud/issues)
- [Discussions](https://github.com/no-problem-dev/swift-llm-cloud/discussions)
- [Release Process](RELEASE_PROCESS.md)
