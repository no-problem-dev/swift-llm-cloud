# ``LLMCloudOpenAI``

OpenAI GPT client covering chat, tools, and image, speech, and video generation, with automatic routing to the Responses API.

## Overview

`OpenAIClient` takes an API key and a `GPTModel`. Model selection is typed, so a Claude or Gemini
model will not compile against it.

The module speaks both OpenAI request shapes. Ordinary calls use Chat Completions; agent steps on a
reasoning model that also has tools are routed to `/v1/responses` instead, and streaming agent
steps always go through `/v1/responses`. You do not choose — the client picks based on the model
and the arguments, because reasoning models drop their chain of thought between Chat Completions
turns and the Responses API is what preserves it.

### What differs from the other providers

**Two APIs, one client.** The Responses API models a turn as typed output *items* rather than a
single message, so a reply can contain reasoning, tool calls, and text side by side.

**Streaming is typed events.** Instead of opaque chunks you get named events such as
`response.output_text.delta`, each mapping to a case rather than requiring you to diff successive
snapshots. Text arrives incrementally; tool calls do not — partial argument deltas are discarded and
the completed response is taken as the truth, because half a JSON object is not something a caller
can act on. Unknown or malformed events are ignored rather than aborting the stream.

**Reasoning tokens are billed and invisible.** They are a subset of the output token count, not an
addition to it, and `max_output_tokens` covers them — a step that thinks hard can exhaust the budget
before emitting any text at all.

**Tool results are matched by `call_id`.** The id from the call must come back on the function
output item, or the model has no way to associate the two.

### Structured output

```swift
import LLMCloudOpenAI

let client = OpenAIClient(apiKey: "sk-...")

@Structured("A support ticket triaged from a customer message")
struct Ticket {
    @StructuredField("One-line summary of the problem")
    var summary: String
    @StructuredField("Severity from 1 (cosmetic) to 5 (outage)", .minimum(1), .maximum(5))
    var severity: Int
}

let ticket: Ticket = try await client.generate(
    input: "Nobody on the team can log in since this morning's deploy.",
    model: .gpt4o
)
```

### Multiple organizations

Pass the organization at construction time when one key is shared across several of them; billing
and rate limits are tracked per organization.

```swift
let client = OpenAIClient(apiKey: "sk-...", organization: "org-...")
```

### Retry

Retry behaviour comes from `LLMCloudClient` and is configured with `RetryConfiguration` at
construction. OpenAI's `x-ratelimit-*` headers are parsed into `RateLimitInfo`, and a rate-limited
response is retried on the window the headers describe rather than on blind backoff.

## Topics

### Client

- ``OpenAIClient``
