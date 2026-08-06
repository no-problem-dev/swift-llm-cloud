import Foundation
import LLMClient
import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMTool

/// `/v1/responses` API のリクエスト/レスポンス変換を集約するユーティリティ。
package enum OpenAIResponsesConverter {
    // MARK: - Messages → InputItems

    /// `LLMMessage` 配列を Responses API の `input` 配列に変換する。
    ///
    /// - 通常テキスト → `{role, content}`
    /// - 画像を含むメッセージ → `{role, content: [{input_text}, {input_image}]}`
    /// - アシスタントの `.toolUse` → `{type: "function_call", call_id, name, arguments}`
    /// - ユーザーの `.toolResult` → `{type: "function_call_output", call_id, output}`
    /// - audio / video / document は Responses API の画像入力に相当するものが無いため
    ///   `LLMError.mediaNotSupported` を throw する。
    /// - `.thinking` はモデル生成の推論であり、本ルートでは再注入しない。
    package static func toInputItems(_ messages: [LLMMessage]) throws -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"
            // テキストと画像は**同じメッセージにまとめる**。分けると画像が
            // どの発言に付いていたのかが失われる
            var parts: [OpenAIResponsesContentPart] = []

            /// 溜めた content を吐く。テキストだけなら文字列のまま送る
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
                    // 連続するテキストは 1 つにまとめる
                    if case .inputText(let previous)? = parts.last {
                        parts[parts.count - 1] = .inputText(previous + text)
                    } else {
                        parts.append(.inputText(text))
                    }

                case .image(let image):
                    parts.append(imagePart(image))

                case .toolUse(let id, let name, let input):
                    // 先行する content があれば先に message として吐く
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
                    // thinking はモデル生成の推論であり、本ルートでは再注入しない。
                    continue
                }
            }

            flush()
        }

        return items
    }

    /// 画像を `input_image` にする。
    ///
    /// base64 は data URI に組み立てる（Responses API は `image_url` に data URI を受ける）。
    /// Files API に上げたものは `file_id` で参照する。
    private static func imagePart(_ image: ImageContent) -> OpenAIResponsesContentPart {
        image.source.fold(
            base64: { .inputImage(url: "data:\(image.mediaType.mimeType);base64,\($0.base64EncodedString())") },
            url: { .inputImage(url: $0.absoluteString) },
            fileReference: { .inputImageFile(fileId: $0) }
        )
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
