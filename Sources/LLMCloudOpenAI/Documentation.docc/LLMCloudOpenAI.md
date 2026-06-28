# ``LLMCloudOpenAI``

OpenAI GPT モデルの Swift クライアント実装。

## Overview

`LLMCloudOpenAI` は OpenAI の Chat Completions API および Responses API に対応した Swift クライアントです。`OpenAIClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップ・画像生成・音声生成・動画生成の各機能を提供します。

モデル選択は `GPTModel` 型に制約されており、型安全なプロバイダー指定が保証されます。reasoning モデルに対するエージェントステップは、Chat Completions ではなく Responses API へ自動的にルーティングされます。

### 構造化出力

`@Structured` マクロで定義した型をそのまま戻り値として指定できます。

```swift
import LLMCloudOpenAI

let client = OpenAIClient(apiKey: "sk-...")

@Structured("商品情報")
struct Product {
    @StructuredField("商品名")
    var name: String
    @StructuredField("価格（円）", .minimum(0))
    var price: Int
}

let result: Product = try await client.generate(
    input: "iPhone 16 Pro は 159,800 円のスマートフォンです。",
    model: .gpt4o
)
print(result.name)   // "iPhone 16 Pro"
print(result.price)  // 159800
```

### 組織 ID の指定

複数組織を使い分ける場合は初期化時に指定します。

```swift
let client = OpenAIClient(
    apiKey: "sk-...",
    organization: "org-..."
)
```

### リトライ設定

`RetryConfiguration` を渡すことでリトライ挙動をカスタマイズできます（`LLMCloudClient` 参照）。

## Topics

### Client

- ``OpenAIClient``
