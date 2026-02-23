[English](README_EN.md) | 日本語

# LLMCloud

マルチプロバイダー LLM クラウドクライアント Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **マルチプロバイダー** - Anthropic Claude、OpenAI GPT、Google Gemini を統一 API で利用
- **統一インターフェース** - プロバイダー間で共通のプロトコルベース設計
- **ストリーミング** - 全プロバイダーで AsyncThrowingStream によるリアルタイム出力
- **Function Calling** - 全プロバイダーでツール呼び出しをサポート
- **構造化出力** - JSON Schema ベースの型安全なレスポンス

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", .upToNextMajor(from: "1.0.0"))
]
```

### モジュール構成

用途に応じて必要なモジュールのみをインポートできます：

| モジュール | 用途 |
|-----------|------|
| `LLMCloud` | アンブレラ（全プロバイダー再エクスポート） |
| `LLMCloudClient` | プロバイダー共通インフラストラクチャ |
| `LLMCloudAnthropic` | Anthropic Claude プロバイダー |
| `LLMCloudOpenAI` | OpenAI GPT プロバイダー |
| `LLMCloudGemini` | Google Gemini プロバイダー |

## クイックスタート

### Anthropic Claude

```swift
import LLMCloudAnthropic

let anthropic = AnthropicProvider(apiKey: "your-api-key")
for try await chunk in anthropic.stream(messages: [
    .user("Swift 6 の並行処理について教えて")
], model: "claude-sonnet-4-20250514") {
    print(chunk.text, terminator: "")
}
```

### OpenAI GPT

```swift
import LLMCloudOpenAI

let openai = OpenAIProvider(apiKey: "your-api-key")
for try await chunk in openai.stream(messages: [
    .user("関数型プログラミングの利点は？")
], model: "gpt-4o") {
    print(chunk.text, terminator: "")
}
```

### Google Gemini

```swift
import LLMCloudGemini

let gemini = GeminiProvider(apiKey: "your-api-key")
for try await chunk in gemini.stream(messages: [
    .user("SwiftUI のベストプラクティスを教えて")
], model: "gemini-2.0-flash") {
    print(chunk.text, terminator: "")
}
```

## ドキュメント

詳細なガイドと API リファレンスは DocC ドキュメントを参照してください。

| ガイド | 内容 |
|-------|------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/) | 全パブリック API |

## 要件

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## 依存関係

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.1.0) - LLM クライアント抽象化

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

## リンク

- [完全なドキュメント](https://no-problem-dev.github.io/swift-llm-cloud/documentation/llmcloud/)
- [Issue報告](https://github.com/no-problem-dev/swift-llm-cloud/issues)
- [ディスカッション](https://github.com/no-problem-dev/swift-llm-cloud/discussions)
- [リリースプロセス](RELEASE_PROCESS.md)
