# ``LLMCloudMistral``

Mistral AI client for structured output, chat, tool calls, and agent steps.

## Overview

`MistralClient` takes an API key and a `MistralModel`. Model selection is typed, so a model from
another provider will not compile against it.

Underneath it is the shared Chat Completions engine from `LLMCloudOpenAICompatible`. Mistral is the
strictest vendor in the package about unknown fields: sending `max_completion_tokens` returns
`422 Extra inputs are not permitted` rather than being ignored, so the client sends `max_tokens`.

```swift
import LLMCloudMistral

let client = MistralClient(apiKey: "...")

@Structured("A translated string with its detected source language")
struct Translation {
    @StructuredField("The translated text")
    var text: String
    @StructuredField("Source language, in English")
    var language: String
}

let result: Translation = try await client.generate(
    input: "Translate to French: \"thank you very much\"",
    model: .large
)
```

Retry and rate-limit handling come from `LLMCloudClient` and are configured with
`RetryConfiguration` at construction.

## Topics

### Client

- ``MistralClient``
