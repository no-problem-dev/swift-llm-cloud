# ``LLMCloudGroq``

Client for open models hosted on Groq, where the draw is latency rather than capability.

## Overview

`GroqClient` takes an API key and a `GroqModel` naming an open-weights model — Llama, Qwen, and
others — served on Groq's inference hardware. Model selection is typed, so a model from another
provider will not compile against it.

Groq runs the same weights everyone else can run, so the reason to pick it is time to first token,
not quality. It suits interactive paths and high-volume classification; it is a poor trade when the
task needs a frontier model.

Underneath it is the shared Chat Completions engine from `LLMCloudOpenAICompatible`. Groq takes
`max_completion_tokens` rather than `max_tokens`, and the client sends the correct field.

```swift
import LLMCloudGroq

let client = GroqClient(apiKey: "gsk_...")

@Structured("Named entities pulled from a sentence")
struct Extraction {
    @StructuredField("People mentioned")
    var names: [String]
    @StructuredField("Places mentioned")
    var places: [String]
}

let result: Extraction = try await client.generate(
    input: "Tanaka and Suzuki travelled from Tokyo to Osaka for the meeting.",
    model: .llama3_3_70b
)
```

Groq meters requests as well as tokens, so a tight loop of small prompts can hit the request
ceiling long before the token ceiling. Rate-limit headers are parsed into `RateLimitInfo` and the
retry policy waits on the window they describe.

## Topics

### Client

- ``GroqClient``
