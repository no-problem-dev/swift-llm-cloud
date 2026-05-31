import LLMCloudClient
import LLMClient
import LLMChat
import Foundation

extension AnthropicClient: ChatCapableClient {
    public func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: ClaudeModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        let enhancedSystemPrompt = buildChatSystemPrompt(base: systemPrompt, schema: T.jsonSchema)
        let anthropicMessages = try messages.map { try AnthropicMessageConverter.convert($0) }

        let outputFormat = AnthropicOutputFormat(type: "json_schema", schema: AnthropicSchemaAdapter().adapt(T.jsonSchema))
        let body = AnthropicRequestBody(
            model: model.id,
            messages: anthropicMessages,
            system: enhancedSystemPrompt.isEmpty ? nil : enhancedSystemPrompt,
            maxTokens: maxTokens ?? Self.chatDefaultMaxTokens,
            temperature: temperature,
            outputConfig: AnthropicOutputConfig(format: outputFormat)
        )

        let (response, _, _) = try await baseProvider.sendBody(body, beta: Self.structuredOutputsBeta)

        guard let rawText = response.content.first(where: { AnthropicBlockType(rawValue: $0.type) == .text })?.text else {
            throw LLMError.emptyResponse
        }
        guard let jsonData = rawText.data(using: .utf8) else {
            throw LLMError.invalidEncoding
        }

        let resultDecoder = JSONDecoder()
        resultDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let result: T
        do {
            result = try resultDecoder.decode(T.self, from: jsonData)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return ChatResponse(
            result: result,
            assistantMessage: .assistant(rawText),
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) },
            model: response.model,
            rawText: rawText
        )
    }

    private static let structuredOutputsBeta = "structured-outputs-2025-11-13"
    private static let chatDefaultMaxTokens = 4096

    private func buildChatSystemPrompt(base: String?, schema: JSONSchema) -> String {
        var parts: [String] = []
        if let base { parts.append(base) }
        if let description = schema.description { parts.append("出力形式: \(description)") }
        return parts.joined(separator: "\n\n")
    }
}
