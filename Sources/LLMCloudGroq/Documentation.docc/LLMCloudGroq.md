# ``LLMCloudGroq``

Groq ホステッドモデルの Swift クライアント実装。

## Overview

`LLMCloudGroq` は Groq の推論インフラ上で動作するモデル（Llama、Qwen など）に対応した Swift クライアント。`GroqClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップの各機能を提供する。

モデル選択は `GroqModel` 型に制約されており、型安全なプロバイダー指定が保証される。Groq は高速推論に特化したインフラを提供するため、低レイテンシーが求められるユースケースに適している。内部的に `LLMCloudOpenAICompatible` の共有エンジンを使用している。

### 基本的な使い方

```swift
import LLMCloudGroq

let client = GroqClient(apiKey: "gsk_...")

@Structured("抽出結果")
struct Extraction {
    @StructuredField("人名")
    var names: [String]
    @StructuredField("地名")
    var places: [String]
}

let result: Extraction = try await client.generate(
    input: "田中さんと鈴木さんは東京から大阪へ出張しました。",
    model: .llama3_3_70b
)
print(result.names)   // ["田中", "鈴木"]
print(result.places)  // ["東京", "大阪"]
```

## Topics

### クライアント

- ``GroqClient``
