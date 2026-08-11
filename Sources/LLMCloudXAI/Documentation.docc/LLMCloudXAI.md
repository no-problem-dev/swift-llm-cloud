# ``LLMCloudXAI``

xAI Grok client for structured output, chat, tool calls, and agent steps.

## Overview

`XAIClient` takes an API key and a `GrokModel`. Model selection is typed, so a model from another
provider will not compile against it.

Underneath it is the shared Chat Completions engine from `LLMCloudOpenAICompatible`. xAI follows
OpenAI's field naming and takes `max_completion_tokens`, which the client sends.

```swift
import LLMCloudXAI

let client = XAIClient(apiKey: "xai-...")

@Structured("Sentiment read off a short piece of text")
struct Analysis {
    @StructuredField("One-sentence summary")
    var summary: String
    @StructuredField("Overall sentiment: positive, negative, or neutral")
    var sentiment: String
}

let result: Analysis = try await client.generate(
    input: "The weather was glorious today and I felt great.",
    model: .grok43
)
```

Retry and rate-limit handling come from `LLMCloudClient` and are configured with
`RetryConfiguration` at construction.

## Topics

### Client

- ``XAIClient``
