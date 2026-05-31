import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI 互換 API プロバイダー（共通実装）
///
/// APIClient + APIContract を使用して OpenAI 互換 API を呼び出す。
/// 各プロバイダーのクライアントから使用される。
package struct OpenAICompatibleProvider: LLMProvider, RetryableProviderProtocol {
    /// APIClient
    private let apiClient: APIClientImpl

    /// プロバイダー名（エラーメッセージ用）
    private let providerName: String

    /// プロバイダー固有のカスタムヘッダー
    private let customHeaders: [String: String]

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: API キー
    ///   - endpoint: 完全なエンドポイント URL
    ///   - providerName: プロバイダー名
    ///   - session: カスタム URLSession（オプション）
    ///   - customHeaders: プロバイダー固有のカスタムヘッダー
    package init(
        apiKey: String,
        endpoint: URL,
        providerName: String,
        session: URLSession = .shared,
        customHeaders: [String: String] = [:]
    ) {
        self.providerName = providerName
        self.customHeaders = customHeaders

        self.apiClient = APIClientImpl(
            baseURL: endpoint,
            transport: URLSessionTransport(session: session),
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .snakeCase
        )
    }

    // MARK: - LLMProvider

    package func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    package func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        // リクエストボディを構築
        let body = try buildRequestBody(from: request)

        // APIContract エンドポイント経由で実行
        let endpoint = OpenAICompatibleAPI.CreateChatCompletion(
            customHeaders: customHeaders,
            request: body
        )

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)

            // LLMResponse に変換
            let llmResponse = OpenAICompatibleResponseConverter.toLLMResponse(apiResponse.output)

            // HTTPURLResponse を構成（RetryableProvider 互換）
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                statusCode: apiResponse.statusCode,
                httpVersion: nil,
                headerFields: apiResponse.headers
            )!

            return (llmResponse, httpResponse)
        } catch let error as LLMError {
            throw error
        } catch let error as RateLimitAwareError {
            throw error
        } catch let error as APIError {
            throw mapAPIError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    // MARK: - Request Building

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

    // MARK: - Error Mapping

    /// APIError を LLMError にマッピング
    private func mapAPIError(_ error: APIError) -> LLMError {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .networkError(let underlying):
            return .networkError(underlying)
        case .decodingError(let underlying):
            return .decodingFailed(underlying)
        case .invalidURL, .invalidResponse:
            return .invalidRequest("Invalid URL or response")
        case .httpError(let statusCode, _):
            return .serverError(statusCode, "HTTP error")
        }
    }
}

// MARK: - Static Token Provider

/// 固定トークンを提供する AuthTokenProvider
private struct StaticTokenProvider: AuthTokenProvider {
    let token: String

    func getToken() async throws -> String? {
        token
    }
}
