# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing.

## [4.0.0] - 2026-07-19

### ⚠️ Breaking Changes

- Updated the swift-api-client dependency to `from: "3.0.0"` (unifying the api-client
  generation across the family). Following the rename of the `AuthTokenProvider`
  requirement in api-client 3.0.0, the internal
  `StaticTokenProvider.getToken()` was renamed to `fetchToken()`.
  It is at `package` access level so there is no public API change, but the dependency's
  major goes up, which affects consumers' resolution graph.

## [3.32.0] - 2026-06-14

Adds the Anthropic `count_tokens` adapter for the context window breakdown.
Follows swift-llm-client 3.8.0 (the `TokenCounting` port).

### Added
- **`AnthropicAPI.CountTokens` endpoint** (`/v1/messages/count_tokens`) and
  `AnthropicCountTokensBody`/`Response`. The body carries only model/system/messages/tools —
  a count_tokens-specific envelope with no `max_tokens`/`stream`.
- **`AnthropicProvider.countTokens(...)`**: reuses **the same converters** as the send path
  (`AnthropicMessageConverter` / `ToolSet.toAnthropicToolDefs()`), guaranteeing
  "what is counted = what is sent".
- **`AnthropicClient.tokenCounter`**: exposes the Anthropic implementation of the `TokenCounting` port.

### Changed
- Raised the `swift-llm-client` dependency to `3.8.0` or later.

## [3.31.0] - 2026-06-14

Follows swift-llm-client 3.7.0 (the multimodal groundwork redesign) and puts the Anthropic
adapter right. Silent fallbacks are wiped out entirely and the conversion logic is pinned
down with golden tests.

### Added
- **Document (PDF) input support**: `MessageContent.document` is converted for every provider.
  Anthropic uses a document block (base64/url/file_id/plain-text source, title/context/citations),
  Gemini uses inlineData/fileData, and OpenAI throws explicitly because it is unsupported.
- **Anthropic Files API**: sends the image/document `fileReference` as `source.type=file` (file_id).
  Automatically adds `anthropic-beta: files-api-2025-04-14` when a file_id is used.
- **Anthropic prompt cache lowering**: converts `PromptCachePolicy.explicitPrefix` into a
  `cache_control` breakpoint (end of system, or the last tool). ttl 5m/1h;
  for 1h it adds the `extended-cache-ttl-2025-04-11` beta.
- Conversion golden tests for the three providers (deterministic JSON comparison).

### Fixed (breaking behavior fixes)
- **Resolved the silent data corruption of the Anthropic image `fileReference`**: it no longer sends
  empty base64 (`data:""`) and uses the correct file source instead.
- **Abolished every silent skip / silent drop**: OpenAI Responses silently ignoring media, and
  OpenAICompatible silently dropping unsupported audio (URL / unsupported format), now throw `LLMError.mediaNotSupported`.

### Internal
- DRY-ed up the conversion dispatch with `MediaSource.fold` (the DTO shapes stay provider-specific).
- Removed the OpenAI-only `ImageContent.detail` reference from `OpenAICompatible`.
- Updated the dependency to swift-llm-client 3.7.0.

## [1.0.0] - 2026-02-23

### Added
- Initial release
- **LLMCloudClient** - shared infrastructure for cloud providers
- **LLMCloudAnthropic** - Anthropic Claude provider
- **LLMCloudOpenAI** - OpenAI GPT provider
- **LLMCloudGemini** - Google Gemini provider
- **LLMCloud** - umbrella module (re-exports every provider)

[Unreleased]: https://github.com/no-problem-dev/swift-llm-cloud/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/no-problem-dev/swift-llm-cloud/releases/tag/v1.0.0
