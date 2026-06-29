# Getting Started

## Installation

`LLMCloudClient` は swift-llm-cloud の内部モジュール。通常は上位のプロバイダーモジュール（`LLMCloudAnthropic` 等）への依存を追加することで自動的に含まれる。

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "3.37.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "LLMCloudAnthropic", package: "swift-llm-cloud"),
    ])
]
```

## Basic Usage

`LLMCloudClient` を直接使う主なユースケースは **カスタムリトライポリシー** の実装。

### カスタムリトライポリシーの実装

`RetryPolicy` プロトコルに準拠した独自ポリシーを定義し、プロバイダーへ注入できる。

```swift
import LLMCloudClient
import LLMCloudAnthropic

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

### リトライイベントの監視

`RetryEventHandler` を渡すと各リトライ試行を監視できる。

```swift
let client = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .default,
    retryEventHandler: { event in
        print("[Retry] attempt=\(event.attempt) reason=\(event.reason) delay=\(event.delaySeconds)s")
    }
)
```
