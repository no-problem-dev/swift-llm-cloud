import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool

/// Translates between the shared LLM types and the wire shapes of the Responses API.
package enum OpenAIResponsesConverter {
    // MARK: - Messages → InputItems

    /// Flattens a conversation into the input items the Responses API expects.
    ///
    /// Unlike Chat Completions, the Responses API takes one flat array in which role-bearing
    /// messages and standalone items sit side by side, so a single message can expand into
    /// several items:
    ///
    /// - Plain text becomes `{role, content}` with a string body.
    /// - A message that carries an image becomes `{role, content: [{input_text}, {input_image}]}`.
    /// - An assistant tool call becomes `{type: "function_call", call_id, name, arguments}`.
    /// - A tool result becomes `{type: "function_call_output", call_id, output}`, and its
    ///   `call_id` has to be the one the model issued or OpenAI rejects the turn.
    /// - Audio, video, and documents have no counterpart in the Responses input format, so they
    ///   raise `LLMError.mediaNotSupported(mediaType:provider:)`.
    /// - Thinking blocks are dropped. They are the model's own reasoning, and this stateless path
    ///   never feeds them back.
    package static func toInputItems(_ messages: [LLMMessage]) throws -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"
            // Text and images stay in the *same* message. Splitting them loses which
            // utterance an image was attached to.
            var parts: [OpenAIResponsesContentPart] = []

            /// Emits the buffered parts. A lone text part is sent as a plain string.
            func flush() {
                guard !parts.isEmpty else {
                    return
                }
                defer { parts = [] }
                if parts.count == 1, case .inputText(let only) = parts[0] {
                    items.append(.message(role: role, content: only))
                } else {
                    items.append(.multipartMessage(role: role, parts: parts))
                }
            }

            for content in message.contents {
                switch content {
                case .text(let text):
                    // Consecutive text blocks are merged into one part.
                    if case .inputText(let previous)? = parts.last {
                        parts[parts.count - 1] = .inputText(previous + text)
                    } else {
                        parts.append(.inputText(text))
                    }

                case .image(let image):
                    parts.append(imagePart(image))

                case .toolUse(let id, let name, let input):
                    // Anything buffered before the call has to go out as a message first,
                    // so the items keep their original order.
                    flush()
                    let argsString = String(data: input, encoding: .utf8) ?? "{}"
                    items.append(.functionCall(callId: id, name: name, arguments: argsString))

                case .toolResult(let toolCallId, _, let resultContent):
                    flush()
                    items.append(.functionCallOutput(
                        callId: toolCallId,
                        output: resultContent.contentValue
                    ))

                case .audio(let audio):
                    throw LLMError.mediaNotSupported(mediaType: audio.mimeType, provider: "OpenAI Responses")
                case .video(let video):
                    throw LLMError.mediaNotSupported(mediaType: video.mimeType, provider: "OpenAI Responses")
                case .document(let document):
                    throw LLMError.mediaNotSupported(mediaType: document.mimeType, provider: "OpenAI Responses")

                case .thinking:
                    // The model's own reasoning is never fed back on this stateless path.
                    continue
                }
            }

            flush()
        }

        return items
    }

    /// Turns an image into an input image part.
    ///
    /// Raw bytes are assembled into a data URI, which the Responses API accepts in `image_url`
    /// alongside ordinary HTTP URLs. An image already uploaded to the Files API is referenced by
    /// `file_id` instead, so it is not re-sent on every turn.
    private static func imagePart(_ image: ImageContent) -> OpenAIResponsesContentPart {
        image.source.fold(
            base64: { .inputImage(url: "data:\(image.mediaType.mimeType);base64,\($0.base64EncodedString())") },
            url: { .inputImage(url: $0.absoluteString) },
            fileReference: { .inputImageFile(fileId: $0) }
        )
    }

    // MARK: - ToolSet → ToolDefs

    /// Converts a tool set into the flat tool definitions the Responses API expects.
    ///
    /// Chat Completions nests the function under a `function` key; the Responses API puts `name`,
    /// `description`, and `parameters` at the top level of each entry. Every tool is sent with
    /// `strict` set, so the schema is adapted to the subset OpenAI accepts in strict mode.
    package static func toToolDefs(_ tools: ToolSet) -> [OpenAIResponsesToolDef] {
        let adapter = OpenAISchemaAdapter()
        return tools.tools.map { tool in
            OpenAIResponsesToolDef(
                name: tool.toolName,
                description: tool.toolDescription,
                parameters: adapter.adapt(tool.inputSchema),
                strict: true
            )
        }
    }

    // MARK: - ToolChoice

    /// Resolves the tool choice to send with the request.
    ///
    /// The key is nil whenever the request carries no tools, because OpenAI rejects a
    /// `tool_choice` that refers to a tool list that is not there. With tools present but no
    /// explicit choice the model is left to decide, and a disabled choice becomes `none` rather
    /// than dropping the tools, so the model still sees what it could have called.
    package static func toToolChoice(_ choice: ToolChoice?, hasTools: Bool) -> OpenAIResponsesToolChoice? {
        guard hasTools else { return nil }
        guard let choice else { return .auto }
        switch choice {
        case .auto: return .auto
        case .required: return .required
        case .disabled: return OpenAIResponsesToolChoice.none
        case .tool(let name): return .tool(name: name)
        }
    }

    // MARK: - Response → LLMResponse

    /// Converts a Responses body into the shared response type.
    ///
    /// The `output` array is walked in order: `function_call` items become tool-use blocks keyed
    /// by their `call_id`, which is the id a later tool result has to echo, and `reasoning` items
    /// become thinking blocks only when they actually carry text — reasoning models routinely
    /// emit an empty reasoning item. Text from every `message` item is concatenated into a single
    /// trailing text block, and unrecognized item types are skipped.
    ///
    /// Token accounting follows what OpenAI billed: `reasoning_tokens` is reported separately but
    /// is already part of the output count, and cached prompt tokens are a subset of the input
    /// count rather than a separate charge, so they are recorded as cache reads with no
    /// cache-creation counterpart. Any cache hit is tagged as the short tier, because OpenAI
    /// caches prompts automatically and exposes no tier or cache control parameter.
    ///
    /// The `status` field is not consulted. The stop reason is inferred from the blocks: a
    /// response holding a tool call reports a tool-use stop and everything else an end of turn,
    /// so a response cut short by `max_output_tokens` is indistinguishable from a complete one.
    package static func toLLMResponse(_ body: OpenAIResponsesResponseBody) -> LLMResponse {
        var blocks: [LLMResponse.ContentBlock] = []
        var aggregatedText = ""

        for item in body.output {
            switch item {
            case .reasoning(let text):
                if let text, !text.isEmpty {
                    blocks.append(.thinking(text: text, signature: nil))
                }
            case .functionCall(_, let callId, let name, let arguments):
                let inputData = arguments.data(using: .utf8) ?? Data("{}".utf8)
                blocks.append(.toolUse(id: callId, name: name, input: inputData))
            case .message(let text):
                aggregatedText += text
            case .unknown:
                continue
            }
        }

        if !aggregatedText.isEmpty {
            blocks.append(.text(aggregatedText))
        }

        let cachedTokens = body.usage?.inputTokensDetails?.cachedTokens
        let usage = TokenUsage(
            inputTokens: body.usage?.inputTokens ?? 0,
            outputTokens: body.usage?.outputTokens ?? 0,
            reasoningTokens: body.usage?.outputTokensDetails?.reasoningTokens,
            cacheReadTokens: cachedTokens,
            cacheCreationTokens: nil,
            cacheTier: (cachedTokens ?? 0) > 0 ? .short : nil
        )

        // A response that holds a tool call stopped in order to make it.
        let stopReason: LLMResponse.StopReason? = blocks.contains { block in
            if case .toolUse = block { return true }
            return false
        } ? .toolUse : .endTurn

        return LLMResponse(
            content: blocks,
            model: body.model ?? "",
            usage: usage,
            stopReason: stopReason
        )
    }
}
