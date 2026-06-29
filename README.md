English | [日本語](./README.ja.md)

# LLMCloud

A multi-provider LLM cloud client Swift package

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **Multi-Provider** — Anthropic Claude, OpenAI GPT, Google Gemini, and more via a unified API
- **Unified Interface** — Common protocol-based design across all providers
- **Streaming** — Real-time output via `AsyncThrowingStream` for all providers
- **Function Calling** — Tool invocation support across all providers
- **Structured Output** — Type-safe responses using `@Structured` macro (JSON Schema auto-generated)

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "3.37.0")
]
```

### Module Structure

Import only the modules you need:

| Module | Purpose |
|--------|---------|
| `LLMCloud` | Umbrella (re-exports Anthropic, OpenAI, Gemini) |
| `LLMCloudClient` | Shared infrastructure (retry, rate limiting, schema conversion) |
| `LLMCloudAnthropic` | Anthropic Claude provider |
| `LLMCloudOpenAI` | OpenAI GPT provider (with Responses API support) |
| `LLMCloudGemini` | Google Gemini provider (with context cache support) |
| `LLMCloudDeepSeek` | DeepSeek provider (V4 Flash/Pro) |
| `LLMCloudXAI` | xAI Grok provider |
| `LLMCloudGroq` | Groq-hosted models (Llama, Qwen, etc.) |
| `LLMCloudMistral` | Mistral AI provider |
| `LLMCloudOpenRouter` | OpenRouter (single interface to multiple providers) |
| `LLMCloudOpenAICompatible` | Shared OpenAI-compatible engine layer |
| `LLMCloudBranding` | Provider brand logos (SwiftUI) |

## Quick Start

### Anthropic Claude

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")

@Structured("Product info")
struct Product {
    @StructuredField("Product name")
    var name: String
    @StructuredField("Price in USD", .minimum(0))
    var price: Double
}

let result: Product = try await client.generate(
    input: "The iPhone 16 Pro costs $999 and is a smartphone.",
    model: .sonnet
)
print(result.name)   // "iPhone 16 Pro"
print(result.price)  // 999.0
```

### OpenAI GPT

```swift
import LLMCloudOpenAI

let client = OpenAIClient(apiKey: "sk-...")

let result: Product = try await client.generate(
    input: "The MacBook Pro costs $1999 and is a laptop.",
    model: .gpt4o
)
```

### Google Gemini

```swift
import LLMCloudGemini

let client = GeminiClient(apiKey: "AIza...")

let result: Product = try await client.generate(
    input: "The AirPods Pro cost $249 and are wireless earbuds.",
    model: .flash25
)
```

## Documentation

| Guide | Description |
|-------|-------------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) | Full public API |

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 3.9.0) — LLM client abstraction
- [swift-structured-data](https://github.com/no-problem-dev/swift-structured-data) (>= 1.1.0) — Structured data conversion
- [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) (>= 2.1.2) — API contract definition
- [swift-api-client](https://github.com/no-problem-dev/swift-api-client) (>= 2.3.1) — HTTP client

## License

MIT License — See [LICENSE](LICENSE) for details

## Links

- [Full Documentation](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/)
- [Report Issues](https://github.com/no-problem-dev/swift-llm-cloud/issues)
- [Discussions](https://github.com/no-problem-dev/swift-llm-cloud/discussions)
- [Release Process](RELEASE_PROCESS.md)
