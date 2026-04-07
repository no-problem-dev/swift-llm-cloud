import LLMCloudClient
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient Streaming Extension

extension GeminiClient {

    /// Google Gemini API をストリーミングモードで呼び出し、テキストチャンクを返す
    ///
    /// `:streamGenerateContent?alt=sse` エンドポイントを使用し、Server-Sent Events を解析して
    /// 各チャンクの `candidates[0].content.parts[0].text` を順次返します。
    ///
    /// ## 使用例
    ///
    /// ```swift
    /// let client = GeminiClient(apiKey: "...")
    ///
    /// for try await chunk in client.streamText(
    ///     input: "日本の四季について教えてください",
    ///     model: .flash3,
    ///     systemPrompt: "簡潔に答えてください"
    /// ) {
    ///     print(chunk, terminator: "")
    /// }
    /// ```
    public func streamText(
        input: LLMInput,
        model: GeminiModel,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        streamText(
            messages: [input.toLLMMessage()],
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// メッセージ配列を使ったストリーミングテキスト生成
    public func streamText(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildStreamingRequest(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )

                    var sseParser = SSELineParser()
                    var lineBuffer = DataLineBuffer()

                    for try await chunk in HTTPStreamingClient.stream(
                        request: request,
                        session: session
                    ) {
                        let lines = lineBuffer.append(chunk)
                        for line in lines {
                            if let event = sseParser.parseLine(line) {
                                if let text = extractTextDelta(from: event) {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    /// ストリーミング用の HTTP リクエストを構築
    private func buildStreamingRequest(
        messages: [LLMMessage],
        model: GeminiModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) throws -> URLRequest {
        let endpoint = URL(string: "\(baseURL)/\(model.id):streamGenerateContent?alt=sse&key=\(apiKey)")!

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var contents: [[String: Any]] = []
        for message in messages {
            let role = message.role == .user ? "user" : "model"
            let textParts: [[String: Any]] = message.contents.compactMap { content in
                if case .text(let text) = content { return ["text": text] }
                return nil
            }
            if !textParts.isEmpty {
                contents.append(["role": role, "parts": textParts])
            }
        }

        var body: [String: Any] = ["contents": contents]

        if let systemPrompt, !systemPrompt.isEmpty {
            body["system_instruction"] = ["parts": [["text": systemPrompt]]]
        }

        var generationConfig: [String: Any] = [:]
        if let temperature {
            generationConfig["temperature"] = temperature
        }
        if let maxTokens {
            generationConfig["maxOutputTokens"] = maxTokens
        }
        if !generationConfig.isEmpty {
            body["generationConfig"] = generationConfig
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// SSE イベントから text delta を抽出
    private func extractTextDelta(from event: SSEParsedEvent) -> String? {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        let textPieces = parts.compactMap { $0["text"] as? String }
        guard !textPieces.isEmpty else { return nil }
        return textPieces.joined()
    }
}
