# ``LLMCloudDeepSeek``

DeepSeek client for structured output, chat, tool calls, and agent steps.

## Overview

`DeepSeekClient` takes an API key and a `DeepSeekModel`. Model selection is typed, so a model from
another provider will not compile against it.

Underneath it is the shared Chat Completions engine from `LLMCloudOpenAICompatible`. The one vendor
difference that matters is the maximum-output-tokens field: DeepSeek takes `max_tokens` and not
`max_completion_tokens`, and the client sends the correct one without being asked.

```swift
import LLMCloudDeepSeek

let client = DeepSeekClient(apiKey: "sk-...")

@Structured("A short analysis of a passage")
struct Analysis {
    @StructuredField("One-paragraph summary")
    var summary: String
    @StructuredField("Key terms, most important first")
    var keywords: [String]
}

let analysis: Analysis = try await client.generate(
    input: "Swift's async/await turns callback pyramids into straight-line code.",
    model: .v4Flash
)
```

Retry and rate-limit handling come from `LLMCloudClient` and are configured with
`RetryConfiguration` at construction, exactly as for the other providers.

## Topics

### Client

- ``DeepSeekClient``
