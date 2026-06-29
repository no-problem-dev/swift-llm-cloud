# ``LLMCloudAnthropic``

Anthropic Claude API のクライアント実装。

## Overview

`LLMCloudAnthropic` は Anthropic Claude API のクライアント実装。`AnthropicClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップ・トークンカウント・ストリーミングの各機能を提供する。

モデル選択は `ClaudeModel` 型に制約されており、型安全なプロバイダー指定が保証される。

### 構造化出力

`@Structured` マクロで定義した型をそのまま戻り値として指定できる。JSON Schema の生成、Anthropic の `output_config.format` への適合、レスポンスのデコードを自動で行う。

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")

@Structured("ユーザー情報")
struct UserInfo {
    @StructuredField("ユーザー名")
    var name: String
    @StructuredField("年齢", .minimum(0))
    var age: Int
}

let result: UserInfo = try await client.generate(
    input: "山田太郎さんは35歳です。",
    model: .sonnet
)
print(result.name)  // "山田太郎"
print(result.age)   // 35
```

### チャット

複数ターンの会話を `chat()` で管理できる。返却される `ChatResponse` にはアシスタントのメッセージが含まれるため、次のターンへの追加が容易。

```swift
var messages: [LLMMessage] = [.user("Swift の async/await を説明してください")]
let response: ChatResponse<Reply> = try await client.chat(
    messages: messages,
    model: .sonnet
)
messages.append(response.assistantMessage)
```

### トークンカウント

実際の送信前にトークン数を見積もれる。`tokenCounter` が返す `TokenCounting` port の `countInputTokens(modelID:systemPrompt:messages:tools:)` を呼ぶ。戻り値は入力トークン数（`Int`）。

```swift
let inputTokens = try await client.tokenCounter.countInputTokens(
    modelID: ClaudeModel.haiku.id,
    systemPrompt: nil,
    messages: [.user("Hello")],
    tools: nil
)
print("Input tokens: \(inputTokens)")
```

## Topics

### はじめに
- <doc:GettingStarted>

### クライアント
- ``AnthropicClient``
