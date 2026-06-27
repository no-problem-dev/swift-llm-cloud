# ``LLMCloudAnthropic``

## Overview

`LLMCloudAnthropic` は Anthropic Claude API のクライアント実装です。`AnthropicClient` を通じて、構造化出力・チャット・ツールコール・エージェントステップ・トークンカウント・ストリーミングの各機能を提供します。

モデル選択は `ClaudeModel` 型に制約されており、型安全なプロバイダー指定が保証されます。

### 構造化出力

`@Structured` マクロで定義した型をそのまま戻り値として指定できます。JSON Schema の生成、Anthropic の `output_config.format` への適合、レスポンスのデコードを自動で行います。

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

複数ターンの会話を `chat()` で管理できます。返却される `ChatResponse` にはアシスタントのメッセージが含まれるため、次のターンへの追加が容易です。

```swift
var messages: [LLMMessage] = [.user("Swift の async/await を説明してください")]
let response: ChatResponse<Reply> = try await client.chat(
    messages: messages,
    model: .sonnet
)
messages.append(response.assistantMessage)
```

### トークンカウント

実際の送信前にトークン数を見積もれます。

```swift
let count = try await client.countTokens(
    messages: [.user("Hello")],
    model: .haiku
)
print("Input tokens: \(count.inputTokens)")
```

## Topics

### Essentials
- <doc:GettingStarted>

### Client
- ``AnthropicClient``

### Models
- `ClaudeModel`
