import Foundation
import LLMClient

/// Rebuilds a complete ``LLMResponse`` from a stream of chat-completion chunks.
///
/// Chat Completions has no counterpart to the Responses API's `response.completed` frame: nothing
/// on the wire carries the finished message, so the only ground truth for the final response is the
/// deltas themselves. This type is that reassembly, kept apart from the transport so it can be
/// exercised against canned frames.
///
/// What it accumulates, and why each one needs care:
/// - **Text** simply concatenates.
/// - **Reasoning** is read from whichever of the three field names the vendor uses.
/// - **Tool calls** arrive as fragments that have to be stitched by `index`; see ``consume(_:)``.
/// - **Usage** is whichever non-`nil` value arrived last, because vendors put it on different
///   frames.
/// - **`finish_reason`** is likewise the last non-`nil` one, since the frame carrying it is not the
///   last frame for vendors that append a usage-only chunk.
package struct OpenAICompatibleStreamAccumulator: Sendable {

    /// A tool call being stitched together across frames.
    private struct PendingToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""
    }

    private var text: String = ""
    private var model: String?
    private var usage: OpenAICompatibleUsage?
    private var finishReason: String?

    /// Tool calls keyed by their wire `index`, so out-of-order frames still land in the right call.
    private var toolCalls: [Int: PendingToolCall] = [:]

    /// Where a fragment goes when the vendor omitted `index`.
    private var lastToolCallIndex: Int?

    package init() {}

    // MARK: - Consuming

    /// Folds one chunk in and returns the deltas a caller should be shown for it.
    ///
    /// Tool-call fragments are placed by `index` when the vendor sends one. When it is missing —
    /// DeepSeek does not document it, and Groq and xAI do not document streamed tool calls at all —
    /// a fragment that introduces an `id` or a function name opens the next slot, and one carrying
    /// only argument text is appended to the slot last touched. That keeps a vendor that streams
    /// one call at a time working without letting a nameless fragment invent a call of its own.
    ///
    /// - Parameter chunk: The decoded frame.
    /// - Returns: Deltas to yield, in wire order. Reasoning precedes text within a frame.
    package mutating func consume(_ chunk: OpenAICompatibleStreamChunk) -> [StreamDelta] {
        if let chunkModel = chunk.model {
            model = chunkModel
        }
        if let chunkUsage = chunk.usage {
            usage = chunkUsage
        }

        var deltas: [StreamDelta] = []

        for choice in chunk.choices ?? [] {
            if let reason = choice.finishReason {
                finishReason = reason
            }

            guard let delta = choice.delta else { continue }

            // DeepSeek and xAI call it `reasoning_content`, OpenRouter calls it `reasoning` and
            // accepts the other as an alias, so take whichever one carries text.
            let thinking = [delta.reasoningContent, delta.reasoning]
                .compactMap(\.?.value)
                .first { !$0.isEmpty }
            if let thinking {
                deltas.append(.thinkingDelta(thinking))
            }

            if let content = delta.content?.value, !content.isEmpty {
                text += content
                deltas.append(.textDelta(content))
            }

            for fragment in delta.toolCalls ?? [] {
                absorb(fragment)
            }
        }

        return deltas
    }

    private mutating func absorb(_ fragment: OpenAICompatibleStreamToolCall) {
        let index: Int
        if let explicit = fragment.index {
            index = explicit
        } else if fragment.id != nil || fragment.function?.name != nil {
            index = (toolCalls.keys.max().map { $0 + 1 }) ?? 0
        } else if let last = lastToolCallIndex {
            index = last
        } else {
            index = 0
        }
        lastToolCallIndex = index

        var call = toolCalls[index] ?? PendingToolCall()
        if let id = fragment.id, !id.isEmpty {
            call.id = id
        }
        if let name = fragment.function?.name, !name.isEmpty {
            call.name = name
        }
        if let arguments = fragment.function?.arguments?.value {
            call.arguments += arguments
        }
        toolCalls[index] = call
    }

    // MARK: - Result

    /// The response assembled from everything consumed so far.
    ///
    /// Text comes first, then the tool calls in wire-index order. A tool call is dropped when no
    /// frame ever supplied its name, because a call without one cannot be dispatched; its id and
    /// arguments would only mislead an agent loop. Usage is zero rather than absent when no vendor
    /// frame reported it — Groq reports counts under a field this parser does not read, so a zero
    /// there means "not reported on the stream", not "free".
    ///
    /// - Parameter fallbackModel: Model id to report when no frame named one.
    package func makeResponse(fallbackModel: String) -> LLMResponse {
        var content: [LLMResponse.ContentBlock] = []

        if !text.isEmpty {
            content.append(.text(text))
        }

        for index in toolCalls.keys.sorted() {
            let call = toolCalls[index]!
            guard let name = call.name else { continue }
            content.append(.toolUse(
                id: call.id ?? "call_\(index)",
                name: name,
                input: Data(call.arguments.utf8)
            ))
        }

        return LLMResponse(
            content: content,
            model: model ?? fallbackModel,
            usage: usage.map(OpenAICompatibleResponseConverter.toTokenUsage) ?? TokenUsage(
                inputTokens: 0,
                outputTokens: 0,
                reasoningTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                cacheTier: nil
            ),
            stopReason: OpenAICompatibleStopReasonMapper.map(finishReason)
        )
    }
}
