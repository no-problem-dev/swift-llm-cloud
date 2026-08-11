# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing.

## [4.4.0] - 2026-08-06

### Fixed
- **A reasoning model with tools always goes to `/v1/responses`.** OpenAI rejects function
  tools on `/v1/chat/completions` for these models whether or not `reasoning_effort` is
  sent — they reason by default, so passing the parameter is beside the point. The routing
  tested `effectiveEffort != nil`, which dropped any call that passed no effort (a
  sub-agent with `reasoningEffort: nil`, say) onto Chat Completions, where it failed every
  time. The route is now decided by the model.

## [4.3.0] - 2026-08-06

### Added
- **Image input through the Responses API.** OpenAI threw `LLMError.mediaNotSupported`, so no
  OpenAI model could be used on a path that attaches images at all. The content of
  `OpenAIResponsesInputItem.message(role:content:)` was a `String`, with structurally nowhere
  to put an image, while the API accepts an array (`input_text` / `input_image`). Added
  `multipartMessage(role:parts:)`, which sends an array **only when an image is present** and
  otherwise keeps sending a plain string, leaving existing behaviour untouched. Base64 goes as
  a data URI, a URL goes as-is, and something from the Files API is referenced by file_id.
  Text and images stay in one message, since splitting them loses which utterance the image
  belonged to. Audio, video and documents are still rejected — there is nothing to map them to.

### Changed
- Reasoning effort is matched to the model.

## [4.2.1] - 2026-07-30

### Changed
- Raised the swift-api-client floor to 3.0.2, to pick up the SSEParser CRLF fix.

## [4.2.0] - 2026-07-30

### Added
- **`streamAgentStep` for the OpenAI Responses API.** `stream` added to
  `OpenAIResponsesRequestBody` (the key is omitted when false, so the non-streaming wire shape
  is unchanged). `OpenAIResponsesStreamEvent` branches on the `type` in the data JSON rather
  than the `event:` line, and interprets only `output_text.delta`,
  `reasoning_*_text.delta`, `completed`, `failed`, `incomplete` and `error`, ignoring the rest
  and `[DONE]`. Deltas are for display; the ground truth is the complete `Response` on
  `response.completed`, run through the existing converter. `OpenAIClient.streamAgentStep`
  always takes the `/v1/responses` route, and the streaming path does not retry, so deltas
  cannot be duplicated.

## [4.1.0] - 2026-07-30

### Added
- **`streamAgentStep` for Gemini**, so the agent path streams. `GeminiStreamAccumulator`
  aggregates chunk by chunk (text deltas yielded as they arrive, a functionCall complete in
  one chunk, usage taken as the cumulative value overwriting the previous, terminated at EOF).
  It streams whether or not thinking is on — that is controlled separately by
  `thinkingConfig`. A cache expiry recovers by recreating and retrying once, but only before
  any delta has been sent. Request construction is extracted into `makeAgentStepRequest` and
  shared with the non-streaming path.

## [4.0.1] - 2026-07-30

### Changed
- Widened the compatible range for swift-structured-data to include 2.x (`1.3.0..<3.0.0`).

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

[Unreleased]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.4.0...HEAD
[4.4.0]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.3.0...4.4.0
[4.3.0]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.2.1...4.3.0
[4.2.1]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.2.0...4.2.1
[4.2.0]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.1.0...4.2.0
[4.1.0]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.0.1...4.1.0
[4.0.1]: https://github.com/no-problem-dev/swift-llm-cloud/compare/4.0.0...4.0.1
[1.0.0]: https://github.com/no-problem-dev/swift-llm-cloud/releases/tag/v1.0.0
