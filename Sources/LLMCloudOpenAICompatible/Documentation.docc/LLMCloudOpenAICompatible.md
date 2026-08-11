# ``LLMCloudOpenAICompatible``

Shared Chat Completions engine, and the place where vendor disagreements about "OpenAI-compatible" are absorbed.

## Overview

`OpenAIClient`, `DeepSeekClient`, `XAIClient`, `GroqClient`, `MistralClient`, and `OpenRouterClient`
all delegate to this module. It implements the Chat Completions request and response shape once —
message conversion, tool-call assembly, stop-reason mapping, and usage decoding — so the vendor
modules only have to declare a base URL, a model enum, and the handful of things their API does
differently.

This path is request/response only. It sends no `stream` field and parses no server-sent events, so
a vendor built solely on this engine returns its answer in one piece. `AnthropicClient`,
`OpenAIClient`, and `GeminiClient` implement token-by-token streaming in their own modules; the
others inherit a default that runs the call to completion and then emits a single event.

Most apps never import it. Import it by name only to reach an OpenAI-compatible endpoint that has
no dedicated module in this package.

### Implementing a client for another endpoint

Provide a model type conforming to ``OpenAICompatibleModelProtocol`` and the shared engine supplies
the rest.

```swift
import LLMCloudClient
import LLMCloudOpenAICompatible

struct MyModel: OpenAICompatibleModelProtocol {
    var id: String
    func toLLMModel() -> LLMModel { .custom(id) }
}
```

### The max-tokens field is not portable

"OpenAI-compatible" is a contract about request and response *shape*, not about the field set. The
name of the maximum-output-tokens field is the clearest case, and sending the wrong one is a hard
error rather than a fallback.

| Value | Field sent | Vendors |
|---|---|---|
| ``OpenAICompatibleMaxTokensParameter/maxCompletionTokens`` | `max_completion_tokens` | OpenAI, Groq, xAI — these treat `max_tokens` as deprecated |
| ``OpenAICompatibleMaxTokensParameter/maxTokens`` | `max_tokens` | Mistral, DeepSeek, OpenRouter — Mistral answers `max_completion_tokens` with `422 Extra inputs are not permitted` |

Each vendor module picks its value at construction, so this is only your concern when writing a
client for an endpoint the package does not ship.

### Other things vendors disagree about

**Tool arguments come back as a JSON string.** The `arguments` field holds text, not an object, so
it is passed through as a string and parsed by the caller.

**Stop reasons are vendor strings.** They are mapped onto the shared stop reason; unrecognised
values fall through rather than throwing, so a vendor inventing a new one degrades the reason
instead of failing the call.

**Retry does not cover every entry point.** Structured generation and agent steps run under the
retry policy; `chat` and tool-call planning go straight to the provider and are sent exactly once.

**Strict structured output rewrites your schema.** At request-build time every object gets
`additionalProperties: false`, every property is moved into `required` with optionals expressed as
nullable, and `pattern`, `format`, numeric ranges, and length and count bounds are stripped, because
strict mode rejects them. Enums survive. The removed constraints are re-injected as system-prompt
instructions, which means the model is asked to honour them rather than made to — validate on the
way out when a violation would be expensive.

**Usage is required, not optional.** The response body declares `usage` non-optional, so a vendor
that omits the block fails to decode rather than reporting zero. Cached prompt tokens are already
counted inside `prompt_tokens` — a breakdown, not an addend, which is the opposite of Anthropic's
separate buckets.

## Topics

### Implementing a client

- ``OpenAICompatibleModelProtocol``

### Vendor differences

- ``OpenAICompatibleMaxTokensParameter``
