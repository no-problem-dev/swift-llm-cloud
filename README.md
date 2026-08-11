English | [日本語](./README.ja.md)

# LLMCloud

One Swift interface for Anthropic Claude, OpenAI GPT, Google Gemini, and five more LLM providers.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **Eight providers, one shape** — Anthropic, OpenAI, Gemini, DeepSeek, xAI, Groq, Mistral, and OpenRouter behind a common protocol
- **Typed model selection** — a Claude model will not compile against an OpenAI client
- **Structured output** — annotate a type with `@Structured` and get it back decoded; the JSON Schema is generated and adapted to each provider's accepted subset
- **Tool calling** — supported on every provider, with the per-vendor id and argument-encoding differences absorbed
- **Token-by-token streaming** — on Anthropic, OpenAI, and Gemini, which implement it natively; the other five return a completed response
- **Retry that reads the response** — a server-supplied rate-limit wait beats computed backoff

## Quick Start

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

Switching providers is an import and a client:

```swift
import LLMCloudOpenAI
let openai = OpenAIClient(apiKey: "sk-...")
let a: Product = try await openai.generate(input: prompt, model: .gpt4o)

import LLMCloudGemini
let gemini = GeminiClient(apiKey: "AIza...")
let b: Product = try await gemini.generate(input: prompt, model: .flash25)
```

## Documentation

- [API reference](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) — every public symbol, per module
- [Module architecture](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/modulearchitecture) — how the package is split and which module to import

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "4.0.0")
]
```

Then depend on the provider you use, not the umbrella:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "LLMCloudAnthropic", package: "swift-llm-cloud"),
])
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## License

MIT License — See [LICENSE](LICENSE) for details
