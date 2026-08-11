# ``LLMCloudClient``

Retry, rate limiting, and schema conversion shared by every provider in swift-llm-cloud.

## Overview

swift-llm-cloud gives Anthropic Claude, OpenAI GPT, Google Gemini, and five OpenAI-compatible
vendors a single Swift interface. `LLMCloudClient` is the layer underneath all of them: it decides
when a failed request is worth retrying and how long to wait, reads the rate-limit headers each
vendor spells differently, and rewrites a `@Structured` JSON Schema into the subset the target
provider will accept.

Apps normally do not import it. Provider modules depend on it, and the common types
(`RetryConfiguration`, `RateLimitInfo`, and the rest) reach you through `@_exported import LLMClient`
when you import a provider. Import it by name when you want to supply your own `RetryPolicy`.

### Retry

`RetryPolicy` is the abstraction. Two implementations ship: `ExponentialBackoffPolicy`, which
doubles the wait after each attempt and adds jitter, and `NoRetryPolicy`, which fails immediately.
`RetryConfiguration` selects one and is injected when the provider is constructed.

The part worth knowing: when the response carried a rate-limit hint, that hint wins. The policy
returns the server-suggested wait rather than its own computed backoff, so a `429` is honoured on
the provider's schedule instead of a guess.

```swift
import LLMCloudAnthropic

let client = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .default
)

let aggressive = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .aggressive,
    retryEventHandler: { event in
        print("Retry \(event.attempt)/\(event.maxRetries): \(event.reason) — waiting \(event.delaySeconds)s")
    }
)
```

### Rate limiting

`RateLimitInfo` holds what could be recovered from the response headers. Vendors do not agree on
header names or on whether they report remaining requests, remaining tokens, or both, so fields are
optional and a missing value means "the provider did not tell us", not zero. `suggestedWaitTime`
feeds the retry delay calculation automatically.

### Schema conversion

Providers accept different subsets of JSON Schema. `WireSchema` is the neutral representation, and
each provider's adapter downgrades it — dropping keywords the vendor rejects, or restructuring for
strict mode. A constraint that survives is enforced by the model; one that gets dropped is not, so
validate on the way out if it matters.

## Topics

### Getting started

- <doc:GettingStarted>

### Retry

- ``RetryPolicy``
- ``ExponentialBackoffPolicy``
- ``NoRetryPolicy``
- ``RetryConfiguration``
- ``RetryableProvider``
- ``RetryableProviderProtocol``
- ``RetryRunner``
- ``RetryEvent``

### Rate limiting

- ``RateLimitInfo``
- ``RateLimitInfoExtractable``
- ``RateLimitAwareError``

### Schema

- ``WireSchema``
