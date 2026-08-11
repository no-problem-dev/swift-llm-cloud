# Getting Started

Replacing the retry behaviour that every provider inherits.

## Overview

`LLMCloudClient` arrives transitively with any provider module, so there is nothing to add to
`Package.swift` for it. The reason to import it by name is to change how failures are handled.

## Writing a custom retry policy

Conform to `RetryPolicy` and inject it through the provider's `retryConfiguration`. The two methods
are asked in order: `shouldRetry(error:attempt:)` decides whether there is another attempt at all,
and `delay(for:error:rateLimitInfo:)` decides how long to wait before it.

`rateLimitInfo` is non-`nil` only when the failing response carried headers the extractor
recognised. Honour its `suggestedWaitTime` before your own arithmetic — it is the provider telling
you when the window reopens, and ignoring it earns another `429`.

```swift
import LLMCloudAnthropic
import LLMCloudClient

struct LinearBackoffPolicy: RetryPolicy {
    let maxRetries: Int = 3

    func shouldRetry(error: LLMError, attempt: Int) -> Bool {
        attempt <= maxRetries && error.isRetryable
    }

    func delay(for attempt: Int, error: LLMError, rateLimitInfo: RateLimitInfo?) -> TimeInterval {
        if let wait = rateLimitInfo?.suggestedWaitTime { return wait }
        return TimeInterval(attempt) * 2.0
    }
}
```

`LLMError.isRetryable` is the shared judgement about which failures are transient: rate limiting,
5xx, timeouts, and transport errors. Authentication failures, malformed requests, blocked content,
and decoding failures are not retried, because repeating them changes nothing.

## Observing retries

Retries are otherwise invisible — a call that succeeded on the third attempt looks exactly like one
that succeeded immediately. Pass a `retryEventHandler` to see them, which is the cheapest way to
find out that a workload is quietly spending most of its wall time waiting on a rate limit.

```swift
let client = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .default,
    retryEventHandler: { event in
        print("[Retry] attempt=\(event.attempt) reason=\(event.reason) delay=\(event.delaySeconds)s")
    }
)
```

The handler is called before the wait, not after, so timestamps mark when the decision was taken.
