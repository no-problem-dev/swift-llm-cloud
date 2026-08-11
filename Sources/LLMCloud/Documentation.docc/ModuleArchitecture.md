# Module Architecture

How swift-llm-cloud is split into modules, and which one to import.

## Overview

The package is deliberately not a single module. Every provider pulls in its own request/response
types, and an app that only talks to Claude should not compile the Gemini video-generation
contract to get there. Importing one provider module compiles that provider plus the shared
infrastructure, and nothing else.

Four layers, bottom to top.

### Layer 0 — Shared infrastructure

`LLMCloudClient` is the floor. It owns everything that is not provider-specific: retry policy
and backoff, rate-limit header parsing, and the conversion of a `@Structured` JSON Schema into the
wire shape a given provider will actually accept. Every provider module depends on it, and it
depends on no provider.

You rarely import it directly. Its common types are re-exported through the provider modules, so
`import LLMCloudAnthropic` already gives you `RetryConfiguration` and `RateLimitInfo`. Import it
explicitly only to write a custom `RetryPolicy`.

### Layer 1 — The OpenAI-compatible engine

`LLMCloudOpenAICompatible` implements the Chat Completions request/response shape once. It exists
because "OpenAI-compatible" is a claim, not a specification: vendors disagree on the maximum-token
field name, on which JSON Schema keywords strict mode accepts, on the spelling of their rate-limit
headers, and on which stop reasons they emit. Those disagreements are absorbed here rather than
duplicated five times.

This engine is request/response only. Providers that need token-by-token streaming implement it in
their own module.

Import it directly only when you are pointing the client at an OpenAI-compatible endpoint that has
no dedicated module in this package.

### Layer 2 — Provider modules

Three providers are implemented against their own native API rather than the compatible engine,
because their capabilities do not fit the Chat Completions shape:

| Module | Provider | Why it is native |
|---|---|---|
| `LLMCloudAnthropic` | Anthropic Claude | Messages API, `count_tokens` pre-flight endpoint, separate cache-read/cache-write token counters |
| `LLMCloudOpenAI` | OpenAI GPT | Responses API — typed output items, typed streaming events, server-side conversation state |
| `LLMCloudGemini` | Google Gemini | Explicit context caching (`cachedContents`), thought signatures, image and video generation |

Five more sit on the compatible engine and add only what differs — base URL, model enum, required
headers, and the maximum-token field spelling:

| Module | Provider |
|---|---|
| `LLMCloudDeepSeek` | DeepSeek |
| `LLMCloudXAI` | xAI Grok |
| `LLMCloudGroq` | Groq-hosted open models |
| `LLMCloudMistral` | Mistral AI |
| `LLMCloudOpenRouter` | OpenRouter, which fans out to many upstream providers |

### Layer 3 — Umbrella and presentation

`LLMCloud` re-exports the shared infrastructure plus the three native providers, so a single
`import LLMCloud` gets you `AnthropicClient`, `OpenAIClient`, and `GeminiClient` together. It does
not include the compatible-engine vendors; import those modules by name.

The umbrella costs compile time proportional to what it re-exports. Prefer importing the one
provider you use.

`LLMCloudBranding` is separate from all of the above and depends on none of it. It carries
provider logos as a bundled asset catalog plus a SwiftUI view to draw them, so an app can render a
provider picker without linking any client code.

## Choosing an import

- One provider, in production → import that provider's module.
- Several providers behind a switch → import each one you actually reach.
- Exploring, or a sample app → `import LLMCloud`.
- A vendor this package does not ship → `LLMCloudOpenAICompatible`.
- Only drawing provider logos → `LLMCloudBranding`.
