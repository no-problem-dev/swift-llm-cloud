# ``LLMCloudOpenRouter``

One client and one key for models from many upstream providers, routed through OpenRouter.

## Overview

`OpenRouterClient` reaches models from Anthropic, OpenAI, Google, xAI, DeepSeek, Meta, Mistral,
Moonshot, and others behind a single API key and a single billing relationship. It is the way to
offer users a model picker without integrating each vendor.

Models are named by string rather than by enum, because OpenRouter's catalogue changes faster than
a release cycle. ``OpenRouterModel`` wraps the identifier, and ``OpenRouterModel/Preset`` is a
curated set of known-good ones with display names and capability profiles attached.

### The trade

What you gain in reach you lose in fidelity. Requests are normalised to the Chat Completions shape,
so capabilities that exist only in a provider's native API — Anthropic's `count_tokens` endpoint,
Gemini's explicit context cache, OpenAI's Responses items — are not reachable here. Rate limits,
latency, and usage accounting are inherited from whichever upstream provider served the request, so
they vary per model rather than per key. When you have settled on one provider, the dedicated module
is the better client.

### Attribution headers

`appName` and `siteUrl` are optional and become the `X-Title` and `HTTP-Referer` headers. They are
what identifies your app on OpenRouter's public leaderboards; omit them and requests are anonymous.

```swift
import LLMCloudOpenRouter

let client = OpenRouterClient(
    apiKey: "sk-or-...",
    appName: "MyApp",
    siteUrl: "https://myapp.example.com"
)

@Structured("An article reduced to a headline and a body")
struct Summary {
    @StructuredField("Headline, under 60 characters")
    var title: String
    @StructuredField("Two or three sentences of body")
    var body: String
}

let summary: Summary = try await client.generate(
    input: articleText,
    model: OpenRouterModel("anthropic/claude-sonnet-4.6")
)
```

An unknown model identifier is rejected by OpenRouter at request time, not at compile time — the
cost of the string-based catalogue.

### Presets

Use a preset when you want a vetted model plus the metadata to show it in a picker.

```swift
let summary: Summary = try await client.generate(
    input: articleText,
    model: OpenRouterModel.Preset.claudeSonnet46.model
)
```

Each preset carries a display name, a context window, tool-calling support, and pricing, so a UI can
be built from `Preset.allCases` without a hardcoded table.

## Topics

### Client

- ``OpenRouterClient``

### Models

- ``OpenRouterModel``
- ``OpenRouterModel/Preset``
