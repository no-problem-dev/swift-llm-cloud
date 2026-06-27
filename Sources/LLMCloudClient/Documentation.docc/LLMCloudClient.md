# ``LLMCloudClient``

## Overview

`LLMCloudClient` は、swift-llm-cloud の全プロバイダーが共有するインフラストラクチャ層です。リトライ・バックオフ、レート制限ヘッダーの解析、JSON Schema のワイヤ変換を担い、各プロバイダーはこのモジュールをベースに実装されます。

通常、アプリ側が `LLMCloudClient` を直接インポートする必要はありません。`LLMCloudAnthropic`、`LLMCloudOpenAI`、`LLMCloudGemini` などのプロバイダーモジュールが内部で依存しており、共通型（`RetryConfiguration`、`RateLimitInfo` など）は `@_exported import LLMClient` 経由で再公開されます。

### リトライ

リトライポリシーは `RetryPolicy` プロトコルで抽象化されています。標準実装として `ExponentialBackoffPolicy`（指数バックオフ＋ジッター）と `NoRetryPolicy`（即失敗）が提供されます。`RetryConfiguration` はポリシーのファクトリとして機能し、プロバイダーの初期化時に注入します。

```swift
import LLMCloudAnthropic

// 指数バックオフ（デフォルト: 最大5回、1〜60秒）
let client = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .default
)

// アグレッシブ設定（最大10回）
let retryClient = AnthropicClient(
    apiKey: "sk-ant-...",
    retryConfiguration: .aggressive,
    retryEventHandler: { event in
        print("Retry \(event.attempt)/\(event.maxRetries): \(event.reason) — wait \(event.delaySeconds)s")
    }
)
```

### レート制限

`RateLimitInfo` は HTTP レスポンスヘッダーから抽出したレート制限情報を保持します。`suggestedWaitTime` を参照することで、プロバイダーが推奨する待機時間を取得できます。この値はリトライポリシーの遅延計算に自動的に使用されます。

## Topics

### Essentials
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

### Rate Limiting
- ``RateLimitInfo``
- ``RateLimitInfoExtractable``
- ``RateLimitAwareError``

### Schema
- ``WireSchema``
