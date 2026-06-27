# Getting Started

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "LLMCloudAnthropic", package: "swift-llm-cloud"),
    ])
]
```

## Basic Usage

### 1. クライアントを作成

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")
```

### 2. 出力型を定義

`@Structured` と `@StructuredField` マクロで型を定義します。

```swift
@Structured("商品情報")
struct Product {
    @StructuredField("商品名")
    var name: String
    @StructuredField("価格（円）", .minimum(0))
    var price: Int
    @StructuredField("カテゴリ")
    var category: String
}
```

### 3. 生成を実行

```swift
let product: Product = try await client.generate(
    input: "iPhone 16 Pro は 159,800 円のスマートフォンです。",
    model: .sonnet
)
print(product.name)      // "iPhone 16 Pro"
print(product.price)     // 159800
print(product.category)  // "スマートフォン"
```

### 4. トークン使用量を取得

```swift
let result: GenerationResult<Product> = try await client.generateWithUsage(
    input: "iPhone 16 Pro は 159,800 円のスマートフォンです。",
    model: .sonnet
)
print("Input: \(result.usage.inputTokens), Output: \(result.usage.outputTokens)")
```

### モデル一覧

| `ClaudeModel` | 説明 |
|---|---|
| `.opus` | Claude Opus — 最高性能 |
| `.sonnet` | Claude Sonnet — バランス型（推奨） |
| `.haiku` | Claude Haiku — 高速・低コスト |
