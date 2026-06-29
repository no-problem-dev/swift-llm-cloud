# ``LLMCloudDeepSeek``

DeepSeek モデルの Swift クライアント実装。

## Overview

`LLMCloudDeepSeek` は DeepSeek API に対応した Swift クライアント。`DeepSeekClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップの各機能を提供する。

モデル選択は `DeepSeekModel` 型に制約されており、型安全なプロバイダー指定が保証される。内部的に `LLMCloudOpenAICompatible` の共有エンジンを使用しており、DeepSeek が `max_tokens` フィールドを要求する差異も自動的に処理される。

### 基本的な使い方

```swift
import LLMCloudDeepSeek

let client = DeepSeekClient(apiKey: "sk-...")

@Structured("分析結果")
struct Analysis {
    @StructuredField("要約")
    var summary: String
    @StructuredField("キーワード")
    var keywords: [String]
}

let result: Analysis = try await client.generate(
    input: "Swift の async/await は並行処理を大幅に簡潔に記述できる機能です。",
    model: .v4Flash
)
print(result.summary)
```

## Topics

### クライアント

- ``DeepSeekClient``
