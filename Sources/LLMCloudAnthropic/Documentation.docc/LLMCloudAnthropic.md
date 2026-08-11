# ``LLMCloudAnthropic``

Anthropic Claude client built on the Messages API, with streaming, tool calls, and pre-flight token counting.

## Overview

`AnthropicClient` is a value type you construct with an API key and hand a model to. The model
parameter is typed as `ClaudeModel`, so a model belonging to another provider will not compile.

Everything the client can do — structured generation, multi-turn chat, tool calls, agent steps,
streaming, and token counting — goes through Anthropic's native Messages API rather than an
OpenAI-compatible shim, because three of those capabilities have no equivalent in the Chat
Completions shape.

### What differs from the other providers

**Token counting is a real request.** Anthropic exposes `/v1/messages/count_tokens`, so
``AnthropicClient/tokenCounter`` returns the number Anthropic itself will bill, not a local
estimate from a tokenizer guess. It costs a round trip and is rate limited separately.

**Cached prompt tokens are reported apart from fresh ones.** Usage carries cache-creation and
cache-read counters in addition to the input count. Adding them together double-counts; the
normalizer in this module folds them into the shared shape correctly.

**`max_tokens` is mandatory.** Anthropic rejects a request without it, where OpenAI defaults. The
client supplies a value when you do not.

### Structured output

Annotate a type with `@Structured`, ask for it as the return type, and the client generates the
JSON Schema, adapts it to Anthropic's output format, and decodes the response.

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")

@Structured("A single step in a recipe")
struct Step {
    @StructuredField("What to do")
    var instruction: String
    @StructuredField("Minutes this step takes", .minimum(0))
    var minutes: Int
}

let step: Step = try await client.generate(
    input: "Simmer the sauce gently for about a quarter of an hour.",
    model: .sonnet
)
```

### Chat

`chat()` returns a `ChatResponse` that already contains the assistant message, so continuing a
conversation is an append rather than a reconstruction.

```swift
var messages: [LLMMessage] = [.user("Explain actor reentrancy in Swift.")]

let response: ChatResponse<Reply> = try await client.chat(messages: messages, model: .sonnet)
messages.append(response.assistantMessage)
```

### Counting tokens before sending

Ask Anthropic what a request will cost before paying for it. This is the only provider in the
package where that number is authoritative.

```swift
let inputTokens = try await client.tokenCounter.countInputTokens(
    modelID: ClaudeModel.haiku.id,
    systemPrompt: nil,
    messages: [.user("Hello")],
    tools: nil
)
```

## Topics

### Getting started

- <doc:GettingStarted>

### Client

- ``AnthropicClient``
