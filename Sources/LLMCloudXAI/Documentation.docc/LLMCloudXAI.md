# ``LLMCloudXAI``

xAI Grok モデルの Swift クライアント実装。

## Overview

`LLMCloudXAI` は xAI の Grok API に対応した Swift クライアント。`XAIClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップの各機能を提供する。

モデル選択は `GrokModel` 型に制約されており、型安全なプロバイダー指定が保証される。内部的に `LLMCloudOpenAICompatible` の共有エンジンを使用している。

### 基本的な使い方

```swift
import LLMCloudXAI

let client = XAIClient(apiKey: "xai-...")

@Structured("分析結果")
struct Analysis {
    @StructuredField("要約")
    var summary: String
    @StructuredField("感情")
    var sentiment: String
}

let result: Analysis = try await client.generate(
    input: "今日は素晴らしい天気で、気分が最高でした。",
    model: .grok43
)
print(result.summary)
print(result.sentiment)  // "ポジティブ"
```

## Topics

### クライアント

- ``XAIClient``
