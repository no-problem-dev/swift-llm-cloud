import Foundation
import LLMClient
import LLMCloudOpenAICompatible
import LLMTool

/// `/v1/responses` API のリクエスト/レスポンス変換を集約するユーティリティ。
package enum OpenAIResponsesConverter {
    // MARK: - Messages → InputItems

    /// `LLMMessage` 配列を Responses API の `input` 配列に変換する。
    ///
    /// - 通常テキスト → `{role, content}`
    /// - アシスタントの `.toolUse` → `{type: "function_call", call_id, name, arguments}`
    /// - ユーザーの `.toolResult` → `{type: "function_call_output", call_id, output}`
    /// - メディア（image/audio/video/document）はこのルート未対応のため `LLMError.mediaNotSupported` を throw する。
    /// - `.thinking` はモデル生成の推論であり、本ルートでは再注入しない。
    package static func toInputItems(_ messages: [LLMMessage]) throws -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"
            var textBuffer = ""

            for content in message.contents {
                switch content {
                case .text(let text):
                    textBuffer += text

                case .toolUse(let id, let name, let input):
                    // 先行するテキストがあれば先に message として吐く
                    if !textBuffer.isEmpty {
                        items.append(.message(role: role, content: textBuffer))
                        textBuffer = ""
                    }
                    let argsString = String(data: input, encoding: .utf8) ?? "{}"
                    items.append(.functionCall(callId: id, name: name, arguments: argsString))

                case .toolResult(let toolCallId, _, let resultContent):
                    if !textBuffer.isEmpty {
                        items.append(.message(role: role, content: textBuffer))
                        textBuffer = ""
                    }
                    items.append(.functionCallOutput(
                        callId: toolCallId,
                        output: resultContent.contentValue
                    ))

                case .image(let image):
                    throw LLMError.mediaNotSupported(mediaType: image.mimeType, provider: "OpenAI Responses")
                case .audio(let audio):
                    throw LLMError.mediaNotSupported(mediaType: audio.mimeType, provider: "OpenAI Responses")
                case .video(let video):
                    throw LLMError.mediaNotSupported(mediaType: video.mimeType, provider: "OpenAI Responses")
                case .document(let document):
                    throw LLMError.mediaNotSupported(mediaType: document.mimeType, provider: "OpenAI Responses")

                case .thinking:
                    // thinking はモデル生成の推論であり、本ルートでは再注入しない。
                    continue
                }
            }

            if !textBuffer.isEmpty {
                items.append(.message(role: role, content: textBuffer))
            }
        }

        return items
    }

    // MARK: - ToolSet → ToolDefs

    /// `ToolSet` を Responses API のフラットなツール定義配列に変換する。
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

    /// `OpenAIResponsesResponseBody` を共通の `LLMResponse` に変換する。
    ///
    /// `function_call` と `message` のテキストを `ContentBlock` に展開し、
    /// `reasoning` は空でない場合のみ `.thinking` ブロックとして保持する。
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

        // ツールコールが含まれていれば stop reason を toolUse に。
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
