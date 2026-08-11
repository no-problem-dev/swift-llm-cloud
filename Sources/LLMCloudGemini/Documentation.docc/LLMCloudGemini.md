# ``LLMCloudGemini``

Google Gemini client with explicit context caching, multimodal input, and image and video generation.

## Overview

`GeminiClient` takes an API key and a `GeminiModel`. It covers structured generation, chat, tool
calls, agent steps, streaming, image generation, video generation via Veo, and Gemini's explicit
prompt cache.

### What differs from the other providers

**The prompt cache is explicit and billed.** Anthropic and OpenAI cache implicitly; Gemini makes you
create a `cachedContents` entry, which has a minimum token count, a TTL you pay for while it lives,
and a binding to one exact model version. Point a cache at a different model and it does not apply.

**Tool calls have no ids.** A `functionCall` part is matched to its `functionResponse` by function
name, not by a `call_id` as with OpenAI. Two outstanding calls to the same tool are not
distinguishable by identity.

**Thought signatures must be echoed back.** Thinking models return an opaque signature that has to
travel with the message on the next turn, or the model loses its reasoning state. Because Gemini
leaves the tool-call id unused, this module carries the signature there and restores it on the way
back. Rebuild message history by hand and you drop it.

**Usage counters are nested, not additive.** `cachedContentTokenCount` is already inside
`promptTokenCount`, and `thoughtsTokenCount` is already inside `candidatesTokenCount`. Summing
either pair double-counts. There is no cache-write counter at all, which is the opposite of
Anthropic's separate buckets.

**Video generation is asynchronous.** Veo returns a long-running operation that is polled to
completion, not a response you await once.

### Structured output

```swift
import LLMCloudGemini

let client = GeminiClient(apiKey: "AIza...")

@Structured("A review broken into its claims")
struct ReviewSummary {
    @StructuredField("Rating from 1 to 5", .minimum(1), .maximum(5))
    var rating: Int
    @StructuredField("Points the reviewer praised")
    var positives: [String]
}

let summary: ReviewSummary = try await client.generate(
    input: "Handling is intuitive and the image quality is superb, but it is heavy.",
    model: .flash25
)
```

Gemini accepts a narrower JSON Schema subset than the other providers. The schema adapter drops
keywords Gemini rejects rather than failing the request, so a constraint that survives is enforced
and one that does not is silently absent.

### Explicit context caching

Cache a long system prompt or document once and reference it across requests to avoid re-sending —
and re-paying for — the same tokens. `GeminiCacheEventHandler` reports the cache lifecycle, which is
the only way to tell a cache hit from a silent miss that is costing full price.

```swift
let client = GeminiClient(
    apiKey: "AIza...",
    cacheEventHandler: { event in
        switch event {
        case .created(let name, _): print("cache created: \(name)")
        case .reused(let name):     print("cache reused: \(name)")
        default: break
        }
    }
)
```

A cache below the model's minimum token threshold is rejected, so short prompts cannot be cached at
all.

## Topics

### Client

- ``GeminiClient``

### Context caching

- ``GeminiCacheEvent``
- ``GeminiCacheEventHandler``
- ``GeminiCachedContentError``
