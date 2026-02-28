import LLMClient
import LLMCloudClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI 互換 API プロバイダー（共通実装）
///
/// OpenAI 互換 API を持つ全プロバイダーの内部実装。
/// 各プロバイダーのクライアントから使用される。
package struct OpenAICompatibleProvider: LLMProvider, RetryableProviderProtocol {
    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession
    private let providerName: String
    private let customHeaders: [String: String]

    private static let defaultMaxTokens = 4096

    package init(
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.providerName = providerName
        self.session = session
        self.customHeaders = customHeaders
    }

    // MARK: - LLMProvider

    package func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    package func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in customHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let body = try buildRequestBody(from: request)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidRequest("Invalid response type")
        }

        let llmResponse = try handleResponse(data: data, httpResponse: httpResponse)
        return (llmResponse, httpResponse)
    }

    // MARK: - Private Helpers

    private func buildRequestBody(from request: LLMRequest) throws -> OpenAICompatibleRequestBody {
        var messages: [OpenAICompatibleMessage] = []

        var responseFormat: OpenAICompatibleResponseFormat?
        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = OpenAISchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            responseFormat = OpenAICompatibleResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAICompatibleJSONSchemaWrapper(
                    name: "response",
                    strict: true,
                    schema: adaptationResult.schema
                )
            )

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        let effectiveSystemPrompt = buildEffectiveSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        if let systemPrompt = effectiveSystemPrompt {
            messages.append(OpenAICompatibleMessage(
                role: "system",
                content: systemPrompt,
                toolCallId: nil,
                toolCalls: nil
            ))
        }

        for message in request.messages {
            messages.append(contentsOf: try OpenAICompatibleMessageConverter.convert(
                message, providerName: providerName
            ))
        }

        return OpenAICompatibleRequestBody(
            model: request.model.id,
            messages: messages,
            maxCompletionTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: request.temperature,
            responseFormat: responseFormat,
            tools: nil,
            toolChoice: nil
        )
    }

    private func buildEffectiveSystemPrompt(base: String?, constraints: SystemPrompt?) -> String? {
        switch (base, constraints) {
        case (let base?, let constraints?):
            return "\(base)\n\n\(constraints.render())"
        case (let base?, nil):
            return base
        case (nil, let constraints?):
            return constraints.render()
        case (nil, nil):
            return nil
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    private func handleResponse(data: Data, httpResponse: HTTPURLResponse) throws -> LLMResponse {
        let rateLimitInfo = OpenAICompatibleRateLimitExtractor.extractRateLimitInfo(from: httpResponse)

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw LLMError.unauthorized
        case 429:
            throw RateLimitAwareError(
                underlyingError: .rateLimitExceeded,
                rateLimitInfo: rateLimitInfo,
                statusCode: 429
            )
        case 400:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw LLMError.invalidRequest(errorResponse?.error.message ?? "Bad request")
        case 404:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw LLMError.modelNotFound(errorResponse?.error.message ?? "Model not found")
        case 500...599:
            let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data)
            throw RateLimitAwareError(
                underlyingError: .serverError(httpResponse.statusCode, errorResponse?.error.message ?? "Server error"),
                rateLimitInfo: rateLimitInfo,
                statusCode: httpResponse.statusCode
            )
        default:
            throw LLMError.serverError(httpResponse.statusCode, "Unexpected status code")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let openAIResponse: OpenAICompatibleResponseBody
        do {
            openAIResponse = try decoder.decode(OpenAICompatibleResponseBody.self, from: data)
        } catch {
            throw LLMError.decodingFailed(error)
        }

        return OpenAICompatibleResponseConverter.toLLMResponse(openAIResponse)
    }
}
