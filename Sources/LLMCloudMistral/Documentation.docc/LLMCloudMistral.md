# ``LLMCloudMistral``

Mistral AI モデルの Swift クライアント実装。

## Overview

`LLMCloudMistral` は Mistral AI の API に対応した Swift クライアント。`MistralClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップの各機能を提供する。

モデル選択は `MistralModel` 型に制約されており、型安全なプロバイダー指定が保証される。Mistral は `max_completion_tokens` を拒否し `max_tokens` のみを受け付けるため、この差異は内部で自動的に処理される。内部的に `LLMCloudOpenAICompatible` の共有エンジンを使用している。

### 基本的な使い方

```swift
import LLMCloudMistral

let client = MistralClient(apiKey: "...")

@Structured("翻訳結果")
struct Translation {
    @StructuredField("翻訳テキスト")
    var text: String
    @StructuredField("言語")
    var language: String
}

let result: Translation = try await client.generate(
    input: "次の日本語をフランス語に翻訳してください: 「ありがとうございます」",
    model: .large
)
print(result.text)      // "Merci beaucoup"
print(result.language)  // "フランス語"
```

## Topics

### クライアント

- ``MistralClient``
