[English](./README.md) | 日本語

# LLMCloud

Anthropic Claude・OpenAI GPT・Google Gemini ほか計 8 プロバイダーを 1 つの Swift インターフェースで扱う。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **8 プロバイダーを同じ形で** — Anthropic・OpenAI・Gemini・DeepSeek・xAI・Groq・Mistral・OpenRouter を共通プロトコルで扱う
- **モデル選択が型安全** — Claude のモデルを OpenAI のクライアントに渡すとコンパイルが通らない
- **構造化出力** — `@Structured` を付けた型がそのままデコードされて返る。JSON Schema は自動生成され、各プロバイダーが受け付ける部分集合へ変換される
- **ツールコール** — 全プロバイダー対応。ID の有無や引数のエンコード形式といったベンダー差はこの層で吸収する
- **トークン単位のストリーミング** — 8 プロバイダーすべてで、各社のストリーミングエンドポイント経由で利用できる
- **レスポンスを読むリトライ** — サーバーが返した待機時間を、計算したバックオフより優先する

## クイックスタート

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")

@Structured("商品情報")
struct Product {
    @StructuredField("商品名")
    var name: String
    @StructuredField("価格（円）", .minimum(0))
    var price: Int
}

let result: Product = try await client.generate(
    input: "iPhone 16 Pro は 159,800 円のスマートフォンです。",
    model: .sonnet
)
print(result.name)   // "iPhone 16 Pro"
print(result.price)  // 159800
```

プロバイダーの切り替えは import とクライアントの差し替えだけ:

```swift
import LLMCloudOpenAI
let openai = OpenAIClient(apiKey: "sk-...")
let a: Product = try await openai.generate(input: prompt, model: .gpt4o)

import LLMCloudGemini
let gemini = GeminiClient(apiKey: "AIza...")
let b: Product = try await gemini.generate(input: prompt, model: .flash25)
```

## ドキュメント

- [API リファレンス](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) — モジュールごとの全パブリックシンボル
- [モジュール構成](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/modulearchitecture) — パッケージの分割方針と、どれを import すべきか

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "6.0.0")
]
```

依存に加えるのはアンブレラではなく、使うプロバイダーのモジュール:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "LLMCloudAnthropic", package: "swift-llm-cloud"),
])
```

## 要件

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照
