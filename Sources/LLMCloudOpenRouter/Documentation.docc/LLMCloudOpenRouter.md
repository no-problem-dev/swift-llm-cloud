# ``LLMCloudOpenRouter``

OpenRouter 経由で複数プロバイダーのモデルを利用するための Swift クライアント実装。

## Overview

`LLMCloudOpenRouter` は OpenRouter API に対応した Swift クライアントです。`OpenRouterClient` を通じて、Anthropic・OpenAI・Google・xAI・DeepSeek・Meta・Mistral など複数プロバイダーのモデルを単一のインターフェースで利用できます。

モデルは `OpenRouterModel` 型で指定します。文字列で任意のモデル ID を指定できるほか、キュレーション済みのプリセットを `OpenRouterModel.Preset` から選択することもできます。内部的に `LLMCloudOpenAICompatible` の共有エンジンを使用しています。

### 任意モデルの指定

```swift
import LLMCloudOpenRouter

let client = OpenRouterClient(
    apiKey: "sk-or-...",
    appName: "MyApp",
    siteUrl: "https://myapp.example.com"
)

@Structured("要約")
struct Summary {
    @StructuredField("タイトル")
    var title: String
    @StructuredField("本文")
    var body: String
}

// 任意のモデル ID を文字列で指定
let result: Summary = try await client.generate(
    input: "長い記事のテキスト...",
    model: OpenRouterModel("anthropic/claude-sonnet-4.6")
)
```

### プリセットの使用

```swift
// キュレーション済みプリセットを使用
let result: Summary = try await client.generate(
    input: "長い記事のテキスト...",
    model: OpenRouterModel.Preset.claudeSonnet46.model
)
```

## Topics

### Client

- ``OpenRouterClient``

### Model

- ``OpenRouterModel``
- ``OpenRouterModel/Preset``
