# ``LLMCloudOpenAICompatible``

OpenAI Chat Completions 互換 API の共有インフラストラクチャ層。

## Overview

`LLMCloudOpenAICompatible` は、OpenAI Chat Completions 互換 API を持つすべてのプロバイダーが共通で利用するエンジン層です。`OpenAIClient`、`DeepSeekClient`、`XAIClient`、`GroqClient`、`MistralClient`、`OpenRouterClient` はこのモジュールを内部依存として持ち、デフォルト実装を介して構造化出力・チャット・ツールコール・エージェントステップの各機能を取得します。

通常、アプリ側が `LLMCloudOpenAICompatible` を直接インポートする必要はありません。各プロバイダーモジュール（`LLMCloudOpenAI` など）を使用してください。独自の OpenAI 互換エンドポイントに接続するカスタムクライアントを実装する場合のみ、このモジュールを直接インポートします。

### OpenAI 互換クライアントの実装

`OpenAICompatibleModelProtocol` に準拠したモデル型を用意することで、任意の OpenAI 互換エンドポイントに接続できます。

```swift
import LLMCloudOpenAICompatible
import LLMCloudClient

struct MyModel: OpenAICompatibleModelProtocol {
    var id: String
    func toLLMModel() -> LLMModel { .custom(id) }
}
```

### max_tokens パラメーター名の差異

OpenAI 互換と称するプロバイダーでも、最大生成トークン数のフィールド名が異なります。`OpenAICompatibleMaxTokensParameter` でプロバイダーごとの差異を吸収します。

- `.maxCompletionTokens` — OpenAI / Groq / xAI（これらは `max_tokens` を deprecated 扱い）
- `.maxTokens` — Mistral / DeepSeek / OpenRouter（`max_completion_tokens` を拒否する）

## Topics

### Protocols

- ``OpenAICompatibleModelProtocol``

### Configuration

- ``OpenAICompatibleMaxTokensParameter``
