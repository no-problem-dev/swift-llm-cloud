[English](./README.md) | 日本語

# LLMCloud

マルチプロバイダー LLM クラウドクライアント Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **マルチプロバイダー** — Anthropic Claude、OpenAI GPT、Google Gemini など主要 LLM を統一 API で利用
- **統一インターフェース** — プロバイダー間で共通のプロトコルベース設計
- **ストリーミング** — 全プロバイダーで `AsyncThrowingStream` によるリアルタイム出力
- **Function Calling** — 全プロバイダーでツール呼び出しをサポート
- **構造化出力** — `@Structured` マクロによる型安全なレスポンス（JSON Schema 自動生成）

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "4.0.0")
]
```

### モジュール構成

用途に応じて必要なモジュールのみをインポートできる：

| モジュール | 用途 |
|-----------|------|
| `LLMCloud` | アンブレラ（Anthropic・OpenAI・Gemini を一括インポート） |
| `LLMCloudClient` | プロバイダー共通インフラ（リトライ・レート制限・スキーマ変換） |
| `LLMCloudAnthropic` | Anthropic Claude プロバイダー |
| `LLMCloudOpenAI` | OpenAI GPT プロバイダー（Responses API 対応） |
| `LLMCloudGemini` | Google Gemini プロバイダー（コンテキストキャッシュ対応） |
| `LLMCloudDeepSeek` | DeepSeek プロバイダー（V4 Flash/Pro） |
| `LLMCloudXAI` | xAI Grok プロバイダー |
| `LLMCloudGroq` | Groq ホステッドモデル（Llama/Qwen 等） |
| `LLMCloudMistral` | Mistral AI プロバイダー |
| `LLMCloudOpenRouter` | OpenRouter（複数プロバイダーへの単一インターフェース） |
| `LLMCloudOpenAICompatible` | OpenAI 互換エンジン共有層 |
| `LLMCloudBranding` | プロバイダーブランドロゴ（SwiftUI） |

## クイックスタート

### Anthropic Claude

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")

@Structured("商品情報")
struct Product {
    @StructuredField("商品名")
    var name: String
    @StructuredField("価格（USD）", .minimum(0))
    var price: Double
}

let result: Product = try await client.generate(
    input: "iPhone 16 Pro は 159,800 円のスマートフォンです。",
    model: .sonnet
)
print(result.name)   // "iPhone 16 Pro"
print(result.price)  // 159800
```

### OpenAI GPT

```swift
import LLMCloudOpenAI

let client = OpenAIClient(apiKey: "sk-...")

let result: Product = try await client.generate(
    input: "MacBook Pro は 348,800 円のノートパソコンです。",
    model: .gpt4o
)
```

### Google Gemini

```swift
import LLMCloudGemini

let client = GeminiClient(apiKey: "AIza...")

let result: Product = try await client.generate(
    input: "AirPods Pro は 39,800 円のワイヤレスイヤホンです。",
    model: .flash25
)
```

## ドキュメント

| ガイド | 内容 |
|-------|------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) | 全パブリック API |

## 要件

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## 依存関係

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 3.9.0) — LLM クライアント抽象化
- [swift-structured-data](https://github.com/no-problem-dev/swift-structured-data) (>= 1.1.0) — 構造化データ変換
- [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) (>= 2.1.2) — API コントラクト定義
- [swift-api-client](https://github.com/no-problem-dev/swift-api-client) (>= 2.3.1) — HTTP クライアント

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照

## リンク

- [完全なドキュメント](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/)
- [Issue 報告](https://github.com/no-problem-dev/swift-llm-cloud/issues)
- [ディスカッション](https://github.com/no-problem-dev/swift-llm-cloud/discussions)
- [リリースプロセス](RELEASE_PROCESS.md)
