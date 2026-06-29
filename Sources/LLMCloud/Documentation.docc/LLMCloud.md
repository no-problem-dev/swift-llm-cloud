# ``LLMCloud``

swift-llm-cloud の主要モジュールをまとめてインポートするアンブレラライブラリ。

## Overview

`LLMCloud` は `LLMCloudClient`、`LLMCloudAnthropic`、`LLMCloudOpenAI`、`LLMCloudGemini` の 4 モジュールを `@_exported import` で再公開するアンブレラターゲット。

複数のプロバイダーを 1 つの `import` 文でまとめて利用したい場合に使用する。特定のプロバイダーのみ使用する場合は、そのプロバイダーのモジュール（`LLMCloudAnthropic` など）を直接インポートした方がコンパイル時間を短縮できる。

```swift
import LLMCloud

// AnthropicClient、OpenAIClient、GeminiClient がすべて利用可能
let anthropic = AnthropicClient(apiKey: "sk-ant-...")
let openai = OpenAIClient(apiKey: "sk-...")
let gemini = GeminiClient(apiKey: "AIza...")
```

### 再公開されるモジュール

- `LLMCloudClient` — リトライ・レート制限・WireSchema などの共有インフラ
- `LLMCloudAnthropic` — Anthropic Claude クライアント
- `LLMCloudOpenAI` — OpenAI GPT クライアント（Responses API 対応）
- `LLMCloudGemini` — Google Gemini クライアント（コンテキストキャッシュ対応）

DeepSeek・xAI・Groq・Mistral・OpenRouter を使用する場合は、それぞれのモジュール（`LLMCloudDeepSeek`、`LLMCloudXAI`、`LLMCloudGroq`、`LLMCloudMistral`、`LLMCloudOpenRouter`）を直接インポートする。`LLMCloud` はこれらを含まない。

## Topics
