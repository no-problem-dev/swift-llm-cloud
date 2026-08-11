# Getting Started

From an API key to a decoded Swift value, and then to the token bill.

## Create a client

`AnthropicClient` is a `struct`. Constructing one performs no I/O and opens no connection, so it is
cheap to hold as a stored property or to build per call.

```swift
import LLMCloudAnthropic

let client = AnthropicClient(apiKey: "sk-ant-...")
```

Keep the key out of the binary. Anything compiled into the app ships to every user who can unzip
it, so read it from the keychain or a server you control.

## Describe the output you want

`@Structured` on the type and `@StructuredField` on each property generate a JSON Schema at compile
time. The description strings are not decoration — they are sent to the model as the field
documentation and are the main lever you have over what ends up in each field.

```swift
@Structured("A parsed shipping address")
struct Address {
    @StructuredField("Street and building number")
    var street: String
    @StructuredField("City name, without prefecture or state")
    var city: String
    @StructuredField("Postal code, digits only")
    var postalCode: String
}
```

Constraints such as `.minimum(0)` are carried in the schema. Whether the model is bound by them is
a property of the provider, not a guarantee of this package — validate on the way out when a bad
value would be expensive.

## Generate

The return type drives the request. Annotate the binding and the client fills in the schema, sends
the message, and decodes the reply.

```swift
let address: Address = try await client.generate(
    input: "Ship it to 1-2-3 Marunouchi, Chiyoda, 100-0005.",
    model: .sonnet
)
```

## Get the usage alongside the value

`generate` throws away the token counts. `generateWithUsage` keeps them, which is what you want as
soon as anyone asks what a feature costs.

```swift
let result: GenerationResult<Address> = try await client.generateWithUsage(
    input: "Ship it to 1-2-3 Marunouchi, Chiyoda, 100-0005.",
    model: .sonnet
)
print(result.usage.inputTokens, result.usage.outputTokens)
```

Input tokens include the schema and the system prompt, not just your text — a large `@Structured`
type is a fixed cost paid on every call.

## Choosing a model

`ClaudeModel` has both floating aliases and pinned versions. The aliases follow Anthropic's current
release; the pinned cases do not move under you.

| Case | Use it for |
|---|---|
| `.opus` | Hard multi-step reasoning where a wrong answer costs more than the tokens |
| `.sonnet` | The default: strong enough for most work, materially cheaper than Opus |
| `.haiku` | High-volume or latency-sensitive paths — classification, extraction, routing |

Pin a version (`.sonnet4_6`, `.opus4_8`, …) when output stability matters more than getting the
newest weights, because an alias moving is indistinguishable from your prompt breaking.
