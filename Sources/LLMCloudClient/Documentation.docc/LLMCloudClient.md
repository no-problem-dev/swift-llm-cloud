# ``LLMCloudClient``

swift-llm-cloud の全プロバイダーが共有するリトライ・レート制限・スキーマ変換のインフラストラクチャ層。

## Overview

`LLMCloudClient` は swift-llm-cloud の全プロバイダーが共有するインフラストラクチャ層。リトライ・バックオフ、レート制限ヘッダーの解析、JSON Schema のワイヤ変換を担い、各プロバイダーはこのモジュールをベースに実装される。

通常、アプリ側が `LLMCloudClient` を直接インポートする必要はない。`LLMCloudAnthropic`、`LLMCloudOpenAI`、`LLMCloudGemini` などのプロバイダーモジュールが内部で依存しており、共通型（`RetryConfiguration`、`RateLimitInfo` など）は `@_exported import LLMClient` 経由で再公開される。

### パッケージの全体構成

swift-llm-cloud は `LLMCloudClient` を中核とした複数モジュールで構成されている。

**プロバイダーモジュール**は各 LLM API への接続実装を提供する。`LLMCloudAnthropic` は Anthropic Claude API（構造化出力・ストリーミング・トークンカウント対応）、`LLMCloudOpenAI` は OpenAI GPT API（Chat Completions + Responses API の自動ルーティング・画像/音声/動画生成対応）、`LLMCloudGemini` は Google Gemini API（明示的プロンプトキャッシュ・マルチモーダル・動画生成対応）をそれぞれ担当する。

**OpenAI 互換プロバイダー**は `LLMCloudOpenAICompatible` が提供する共有エンジンを通じて実装される。`LLMCloudDeepSeek`（DeepSeek-V4 Flash/Pro）、`LLMCloudXAI`（xAI Grok）、`LLMCloudGroq`（Groq ホステッドの Llama/Qwen 等）、`LLMCloudMistral`（Mistral AI）、`LLMCloudOpenRouter`（複数プロバイダーのモデルに単一インターフェースでアクセス）が含まれる。

**アンブレラターゲット** `LLMCloud` は `LLMCloudClient`・`LLMCloudAnthropic`・`LLMCloudOpenAI`・`LLMCloudGemini` を 1 つの `import` で利用できるように再公開する。

**表示資産** `LLMCloudBranding` は各プロバイダーのブランドロゴ（`ProviderLogos.xcassets` 同梱）と SwiftUI ビューを提供する。他のターゲットへの依存はなく、純粋な UI 層として分離されている。

### リトライ

リトライポリシーは `RetryPolicy` プロトコルで抽象化されている。標準実装として `ExponentialBackoffPolicy`（指数バックオフ＋ジッター）と `NoRetryPolicy`（即失敗）が提供される。`RetryConfiguration` はポリシーのファクトリとして機能し、プロバイダーの初期化時に注入する。

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

`RateLimitInfo` は HTTP レスポンスヘッダーから抽出したレート制限情報を保持する。`suggestedWaitTime` を参照することで、プロバイダーが推奨する待機時間を取得できる。この値はリトライポリシーの遅延計算に自動的に使用される。

## Topics

### はじめに
- <doc:GettingStarted>

### リトライ
- ``RetryPolicy``
- ``ExponentialBackoffPolicy``
- ``NoRetryPolicy``
- ``RetryConfiguration``
- ``RetryableProvider``
- ``RetryableProviderProtocol``
- ``RetryRunner``
- ``RetryEvent``

### レート制限
- ``RateLimitInfo``
- ``RateLimitInfoExtractable``
- ``RateLimitAwareError``

### スキーマ
- ``WireSchema``
