# ``LLMCloud``

Umbrella module that re-exports the shared infrastructure and the three natively implemented providers.

## Overview

`LLMCloud` declares no symbols of its own. It is a single `@_exported import` of `LLMCloudClient`,
`LLMCloudAnthropic`, `LLMCloudOpenAI`, and `LLMCloudGemini`, so one import statement brings all
three clients into scope.

```swift
import LLMCloud

let anthropic = AnthropicClient(apiKey: "sk-ant-...")
let openai = OpenAIClient(apiKey: "sk-...")
let gemini = GeminiClient(apiKey: "AIza...")
```

Use it when you are comparing providers or writing a sample. In an app that ships one provider,
import that provider's module instead — the umbrella compiles all four.

### What it does not include

DeepSeek, xAI, Groq, Mistral, and OpenRouter are not re-exported. They are built on the
OpenAI-compatible engine rather than a native API, and pulling them in would make the umbrella the
whole package. Import `LLMCloudDeepSeek`, `LLMCloudXAI`, `LLMCloudGroq`, `LLMCloudMistral`, or
`LLMCloudOpenRouter` directly.

`LLMCloudBranding` is also excluded: it is a SwiftUI presentation module with no client code and no
dependency on the rest of the package.

## Topics

### Package structure

- <doc:ModuleArchitecture>
