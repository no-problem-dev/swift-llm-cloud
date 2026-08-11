# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [5.0.0] - 2026-08-11

### Fixed

- **`generateWithUsage` and `generate` recursed forever on every cloud client.** Both were
  unreachable at run time on `AnthropicClient`, `GeminiClient`, `OpenAIClient`, `DeepSeekClient`,
  `GroqClient`, `MistralClient`, `OpenRouterClient` and `XAIClient` — a call never returned, and
  the process grew until it was killed. The requirement in llm-client 3.x took
  `systemPrompt: SystemPrompt?` while every implementation here declared `systemPrompt: String?`,
  so none of them witnessed it. The convenience method beside the requirement — same signature,
  optional arguments defaulted — witnessed it instead and called straight back into itself. It
  compiled, and no test called either method, so nothing ever said so. llm-client 4.0.0 gives the
  requirement a distinct signature, which turned this into a compile error and is how it was
  found. Confirmed against 3.13.0 in a throwaway package: 85 GB of memory before the kernel
  killed it, with neither implementation ever entered.

### Removed

- **BREAKING — the methods that implement llm-client's protocol requirements now take an options
  value** instead of a list of optional arguments, following llm-client 4.0.0. Gone from the
  public API:

  | Type | Removed |
  |---|---|
  | `AnthropicClient`, `GeminiClient` | `generateWithUsage(input:model:systemPrompt:temperature:maxTokens:)`, `generateWithUsage(messages:model:systemPrompt:temperature:maxTokens:)`, `chat(messages:model:systemPrompt:temperature:maxTokens:)` |
  | `OpenAIClient`, `DeepSeekClient`, `GroqClient`, `MistralClient`, `OpenRouterClient`, `XAIClient` | the same three, inherited from `OpenAICompatibleClientProtocol` |
  | `GeminiClient`, `OpenAIClient` | `generateImage(input:model:size:quality:format:n:)`, `generateImages(input:model:size:quality:format:n:)`, `startVideoGeneration(input:model:duration:aspectRatio:resolution:)` |
  | `OpenAIClient` | `generateSpeech(input:model:voice:speed:format:)` |

  Each is replaced by a form taking `GenerationOptions`, `ChatOptions`, `ImageGenerationOptions`,
  `VideoGenerationOptions` or `SpeechGenerationOptions`.

  **Most call sites need no change.** llm-client still supplies the same argument lists as
  convenience methods with defaults, so `client.generateImage(input:, model:, size: .square1024)`
  and `client.chat(messages:, model:, systemPrompt: "…")` still compile and now reach a real
  implementation. What breaks is passing a `String` variable as `generateWithUsage`'s system
  prompt: the surviving overload takes `SystemPrompt`, which a string *literal* converts to but a
  `String` does not — wrap it as `SystemPrompt(stringLiteral: text)` or pass the literal directly.
  Code that conformed its own type to these protocols by forwarding to a cloud client must adopt
  the options-taking signatures too, or it will no longer conform.

### Changed

- Raised the floors to llm-client 4.0.0, swift-structured-data 3.0.0 and swift-api-client 3.0.3,
  and added a direct dependency on swift-http-transport 1.1.2. api-client 3.0.3 stopped
  re-exporting `HTTPTransport`, and this package names `HTTPTransport`, `HTTPStreamingTransport`,
  `URLSessionTransport` and `SSEEvent` internally, so it now depends on and imports that module
  itself. None of those types appear in this package's public API, so nothing is asked of
  consumers beyond resolving the new floors.

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
