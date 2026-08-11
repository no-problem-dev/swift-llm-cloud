import LLMClient
import LLMCloudClient
import LLMTool
import LLMAgentStep
import LLMChat
import APIClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every OpenAI-compatible capability in one value, so each vendor client is a thin shell over it.
///
/// The DeepSeek, Groq, Mistral, OpenRouter, and xAI clients each hold one engine and conform to
/// ``OpenAICompatibleClientProtocol``, whose default implementations forward straight here. What
/// differs between those vendors is only the endpoint, the extra headers, and the field name used
/// for the token cap.
package struct OpenAICompatibleEngine: Sendable {
    /// The provider handed to callers, retry-wrapped when the retry configuration is enabled.
    ///
    /// `generateWithUsage` sends through this one, so it is the only entry point that gets the
    /// full retry treatment including rate-limit-header-aware backoff.
    package let provider: any LLMProvider

    /// The provider without the retry wrapper.
    ///
    /// `chat` and `planToolCalls` send through it exactly once and are not retried at all;
    /// `executeAgentStep` wraps it in a `RetryRunner` that applies the same policy
    /// `RetryableProvider` would.
    let baseProvider: OpenAICompatibleProvider

    package let apiKey: String

    package let endpoint: URL

    package let session: URLSession

    /// Vendor name reported in unsupported-media errors raised while converting messages.
    package let providerName: String

    /// Headers added to every request, such as OpenRouter's `X-Title` and `HTTP-Referer`.
    package let customHeaders: [String: String]

    /// Which field name carries the token cap for this vendor.
    package let maxTokensParameter: OpenAICompatibleMaxTokensParameter

    package let retryConfiguration: RetryConfiguration

    package let retryEventHandler: RetryEventHandler?

    private static let defaultMaxTokens = 4096

    package init(
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, providerName: providerName,
            session: session, customHeaders: customHeaders,
            maxTokensParameter: maxTokensParameter,
            retryConfiguration: retryConfiguration, retryEventHandler: retryEventHandler
        )
    }

    /// Designated initializer taking an injected transport, so tests can substitute a mock.
    package init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:],
        maxTokensParameter: OpenAICompatibleMaxTokensParameter = .maxCompletionTokens,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.providerName = providerName
        self.session = session
        self.customHeaders = customHeaders
        self.maxTokensParameter = maxTokensParameter
        self.retryConfiguration = retryConfiguration
        self.retryEventHandler = retryEventHandler

        let baseProvider = OpenAICompatibleProvider(
            transport: transport,
            apiKey: apiKey,
            endpoint: endpoint,
            providerName: providerName,
            customHeaders: customHeaders,
            maxTokensParameter: maxTokensParameter
        )
        self.baseProvider = baseProvider

        if retryConfiguration.isEnabled {
            self.provider = RetryableProvider(
                provider: baseProvider,
                extractorType: OpenAICompatibleRateLimitExtractor.self,
                retryPolicy: retryConfiguration.policy,
                eventHandler: retryEventHandler
            )
        } else {
            self.provider = baseProvider
        }
    }

    // MARK: - StructuredLLMClient

    package func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        modelId: String,
        toLLMModel: @Sendable () -> LLMModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        try await generateWithUsage(
            messages: [input.toLLMMessage()],
            modelId: modelId,
            toLLMModel: toLLMModel,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    package func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        modelId: String,
        toLLMModel: @Sendable () -> LLMModel,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        let enhancedSystemPrompt = buildSystemPrompt(base: systemPrompt, schema: T.jsonSchema)

        let request = LLMRequest(
            model: toLLMModel(),
            messages: messages,
            systemPrompt: enhancedSystemPrompt,
            responseSchema: T.jsonSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let response = try await provider.send(request)
        return try OpenAICompatibleResponseConverter.toGenerationResult(response, model: modelId)
    }

    // MARK: - ChatCapableClient

    package func chat<T: StructuredProtocol>(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: String?,
        responseSchema: JSONSchema,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ChatResponse<T> {
        // Goes through the contract like every other send, so schema adaptation, the constraint
        // prompt, and the vendor's token-cap field name are decided in one place and errors arrive
        // as decoded vendor messages. This send is not retried.
        let request = LLMRequest(
            model: .custom(modelId),
            messages: messages,
            systemPrompt: systemPrompt,
            responseSchema: responseSchema,
            temperature: temperature,
            maxTokens: maxTokens
        )
        let (output, _, _) = try await baseProvider.sendRaw(request)
        return try OpenAICompatibleResponseConverter.toChatResponse(output)
    }

    // MARK: - ToolCallableClient

    /// Asks the model which tools to call, without running any of them.
    ///
    /// The vendor returns tool arguments as a JSON string rather than an object, so they are passed
    /// on as raw UTF-8 data for the caller to decode. Any tool call whose type is not `function`
    /// is dropped during conversion and never reaches the caller. This send is not retried.
    package func planToolCalls(
        messages: [LLMMessage],
        modelId: String,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> ToolCallResponse {
        var openAIMessages: [OpenAICompatibleMessage] = []

        if let systemPrompt = systemPrompt {
            openAIMessages.append(OpenAICompatibleMessage(
                role: "system", content: systemPrompt, toolCallId: nil, toolCalls: nil
            ))
        }

        for message in messages {
            openAIMessages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        let body = OpenAICompatibleRequestBody(
            model: modelId,
            messages: openAIMessages,
            maxCompletionTokens: maxTokens ?? Self.defaultMaxTokens,
            maxTokensParameter: maxTokensParameter,
            temperature: temperature,
            responseFormat: nil,
            tools: tools.toOpenAIToolDefs(),
            toolChoice: toolChoice.map { mapToolChoice($0) }
        )
        // The body already carries the vendor's token-cap field name. This send is not retried.
        let (output, _, _) = try await baseProvider.sendBody(body)
        return OpenAICompatibleResponseConverter.toToolCallResponse(output)
    }

    // MARK: - AgentCapableClient

    /// Runs one agent turn, with tools, an optional strict response schema, and a reasoning effort.
    ///
    /// When the tool set is empty, neither `tools` nor `tool_choice` is put in the body; when tools
    /// are present and the caller expressed no preference, `tool_choice` goes out as `auto`.
    /// Temperature is never sent on this path. Retries run through `RetryRunner` rather than the
    /// wrapped provider, but under the same policy.
    package func executeAgentStep(
        messages: [LLMMessage],
        modelId: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?
    ) async throws -> LLMResponse {
        var openAIMessages: [OpenAICompatibleMessage] = []

        if let prompt = systemPrompt {
            openAIMessages.append(OpenAICompatibleMessage(
                role: "system", content: prompt.render(), toolCallId: nil, toolCalls: nil
            ))
        }

        for message in messages {
            openAIMessages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        let openAITools: [OpenAICompatibleToolDef]? = tools.isEmpty ? nil : tools.toOpenAIToolDefs()
        let openAIToolChoice: OpenAICompatibleToolChoice? = tools.isEmpty ? nil : (toolChoice.map { mapToolChoice($0) } ?? .auto)

        var responseFormat: OpenAICompatibleResponseFormat?
        if let schema = responseSchema {
            let adapter = OpenAISchemaAdapter()
            responseFormat = OpenAICompatibleResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAICompatibleJSONSchemaWrapper(
                    name: "response",
                    strict: true,
                    schema: adapter.adapt(schema)
                )
            )
        }

        let body = OpenAICompatibleRequestBody(
            model: modelId,
            messages: openAIMessages,
            maxCompletionTokens: maxTokens ?? Self.defaultMaxTokens,
            maxTokensParameter: maxTokensParameter,
            temperature: nil,
            responseFormat: responseFormat,
            tools: openAITools,
            toolChoice: openAIToolChoice,
            reasoningEffort: reasoningEffort?.rawValue
        )

        // Retries come from RetryRunner, the same domain-aware policy RetryableProvider applies,
        // rather than from a helper specific to the agent path.
        let output = try await RetryRunner.run(
            policy: retryConfiguration.policy,
            eventHandler: retryEventHandler
        ) {
            try await baseProvider.sendBody(body).0
        }
        return OpenAICompatibleResponseConverter.toLLMResponse(output)
    }

    // MARK: - Private Helpers

    /// Appends the schema description to the caller's prompt, restating in prose what the strict
    /// schema already encodes.
    private func buildSystemPrompt(base: String?, schema: JSONSchema) -> String {
        var parts: [String] = []

        if let base = base {
            parts.append(base)
        }

        if let description = schema.description {
            parts.append("出力形式: \(description)")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    private func mapToolChoice(_ choice: ToolChoice) -> OpenAICompatibleToolChoice {
        switch choice {
        case .auto:
            return .auto
        case .disabled:
            return .none
        case .required:
            return .required
        case .tool(let name):
            return .function(name)
        }
    }
}
