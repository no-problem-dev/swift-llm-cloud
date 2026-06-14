# 変更履歴

このプロジェクトの全ての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/spec/v2.0.0.html) に準拠しています。

## [未リリース]

なし

## [3.32.0] - 2026-06-14

コンテキストウィンドウ内訳のための Anthropic `count_tokens` アダプタを追加。
swift-llm-client 3.8.0（`TokenCounting` port）に追従。

### 追加
- **`AnthropicAPI.CountTokens` エンドポイント**（`/v1/messages/count_tokens`）と
  `AnthropicCountTokensBody`/`Response`。ボディは model/system/messages/tools のみで
  `max_tokens`/`stream` を持たない count_tokens 専用 envelope。
- **`AnthropicProvider.countTokens(...)`**: send パスと**同一の変換器**
  （`AnthropicMessageConverter` / `ToolSet.toAnthropicToolDefs()`）を再利用し、
  「数える内容 = 送る内容」を保証。
- **`AnthropicClient.tokenCounter`**: `TokenCounting` port の Anthropic 実装を公開。

### 変更
- `swift-llm-client` 依存を `3.8.0` 以上へ。

## [3.31.0] - 2026-06-14

swift-llm-client 3.7.0（マルチモーダル基盤再設計）への追従と、Anthropic アダプタの
正当化。silent fallback を全面撲滅し、変換ロジックをゴールデンテストで固定した。

### 追加
- **ドキュメント(PDF)入力対応**: `MessageContent.document` を全プロバイダで変換。
  Anthropic は document block（base64/url/file_id/plain-text source、title/context/citations）、
  Gemini は inlineData/fileData、OpenAI は非対応のため明示的に throw。
- **Anthropic Files API**: image/document の `fileReference` を `source.type=file`（file_id）で送出。
  file_id 使用時に `anthropic-beta: files-api-2025-04-14` を自動付与。
- **Anthropic プロンプトキャッシュ lowering**: `PromptCachePolicy.explicitPrefix` を
  `cache_control` ブレークポイント（system 末尾 or 最後の tool）へ変換。ttl 5m/1h、
  1h 時は `extended-cache-ttl-2025-04-11` beta を付与。
- 3 プロバイダの変換ゴールデンテスト（決定論的 JSON 比較）。

### 修正（破壊的挙動修正）
- **Anthropic image `fileReference` の silent データ破損を解消**: 空 base64（`data:""`）送出を廃止し
  正しい file source へ。
- **silent skip / silent drop の全廃**: OpenAI Responses のメディア黙殺、OpenAICompatible の
  非対応 audio（URL/未対応フォーマット）の暗黙ドロップを `LLMError.mediaNotSupported` の throw に。

### 内部
- `MediaSource.fold` による変換ディスパッチの DRY 化（DTO 形状は各プロバイダ固有のまま）。
- `OpenAICompatible` から OpenAI 専用 `ImageContent.detail` 参照を削除。
- 依存を swift-llm-client 3.7.0 へ更新。

## [1.0.0] - 2026-02-23

### 追加
- 初回リリース
- **LLMCloudClient** - クラウドプロバイダー共通インフラストラクチャ
- **LLMCloudAnthropic** - Anthropic Claude プロバイダー
- **LLMCloudOpenAI** - OpenAI GPT プロバイダー
- **LLMCloudGemini** - Google Gemini プロバイダー
- **LLMCloud** - アンブレラモジュール（全プロバイダー再エクスポート）

[未リリース]: https://github.com/no-problem-dev/swift-llm-cloud/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/no-problem-dev/swift-llm-cloud/releases/tag/v1.0.0
