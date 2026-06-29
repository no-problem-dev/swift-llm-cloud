# ``LLMCloudGemini``

Google Gemini モデルの Swift クライアント実装。

## Overview

`LLMCloudGemini` は Google Gemini API に対応した Swift クライアント。`GeminiClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップ・画像生成・動画生成（Veo）・明示的プロンプトキャッシュ（`cachedContents`）の各機能を提供する。

モデル選択は `GeminiModel` 型に制約されており、型安全なプロバイダー指定が保証される。

### 構造化出力

```swift
import LLMCloudGemini

let client = GeminiClient(apiKey: "AIza...")

@Structured("レビュー要約")
struct ReviewSummary {
    @StructuredField("評価（1〜5）", .minimum(1), .maximum(5))
    var rating: Int
    @StructuredField("ポジティブな点")
    var positives: [String]
}

let summary: ReviewSummary = try await client.generate(
    input: "このカメラは操作が直感的で画質も素晴らしいです。ただし重さが気になります。",
    model: .flash25
)
print(summary.rating)     // 4
print(summary.positives)  // ["直感的な操作", "素晴らしい画質"]
```

### 明示的プロンプトキャッシュ

長いシステムプロンプトやドキュメントを `cachedContents` に保持することで、繰り返しリクエストのコストを削減できる。キャッシュのライフサイクルイベントは `GeminiCacheEventHandler` で観測できる。

```swift
let client = GeminiClient(
    apiKey: "AIza...",
    cacheEventHandler: { event in
        switch event {
        case .created(let name, _): print("キャッシュ作成: \(name)")
        case .reused(let name):     print("キャッシュ再利用: \(name)")
        default: break
        }
    }
)
```

## Topics

### クライアント

- ``GeminiClient``

### コンテキストキャッシュ

- ``GeminiCacheEvent``
- ``GeminiCacheEventHandler``
- ``GeminiCachedContentError``
