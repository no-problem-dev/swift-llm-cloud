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

    /// エンドポイント URL（レスポンスメタデータ構成用）
    private let endpoint: URL

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
        self.init(
            transport: URLSessionTransport(session: session),
            apiKey: apiKey, endpoint: endpoint, providerName: providerName, customHeaders: customHeaders
        )
    }

    /// Transport を注入する指定イニシャライザ（テストで MockTransport を差し込む）。
    package init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        endpoint: URL,
        providerName: String,
        customHeaders: [String: String] = [:]
    ) {
        self.providerName = providerName
        self.customHeaders = customHeaders
        self.endpoint = endpoint
        self.apiClient = APIClientImpl(
            baseURL: endpoint,
            transport: transport,
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
        let (output, statusCode, headers) = try await sendRaw(request)
        let llmResponse = OpenAICompatibleResponseConverter.toLLMResponse(output)
        // HTTPURLResponse を構成（RetryableProvider 互換）
        let httpResponse = HTTPURLResponse(
            url: endpoint, statusCode: statusCode, httpVersion: nil, headerFields: headers
        )!
        return (llmResponse, httpResponse)
    }

    /// LLMRequest を contract(CreateChatCompletion)経由で送信し、生レスポンスボディを返す。
    /// 全ての非ストリーミング呼び出し(send / chat / planToolCalls)が通る単一の HTTP 経路。
    /// エラーは contract の decodeError(リッチ)と APIError マッピングで統一される。
    package func sendRaw(_ request: LLMRequest) async throws -> (OpenAICompatibleResponseBody, Int, [String: String]) {
        try await sendBody(buildRequestBody(from: request))
    }

    /// 構築済みのリクエストボディを contract 経由で送信する（tools 付き等、buildRequestBody で
    /// 表現できないリクエストはこちらを使う）。
    package func sendBody(_ body: OpenAICompatibleRequestBody) async throws -> (OpenAICompatibleResponseBody, Int, [String: String]) {
        let contract = OpenAICompatibleAPI.CreateChatCompletion(customHeaders: customHeaders, request: body)
        do {
            let apiResponse = try await apiClient.executeWithResponse(contract)
            return (apiResponse.output, apiResponse.statusCode, apiResponse.headers)
        } catch let error as LLMError {
            throw error
        } catch let error as RateLimitAwareError {
            throw error
        } catch let error as APIError {
            throw mapAPIErrorToLLMError(error)
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

        let effectiveSystemPrompt = composeSystemPrompt(
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


    // MARK: - Error Mapping

    /// APIError を LLMError にマッピング
}

// MARK: - Static Token Provider

/// 固定トークンを提供する AuthTokenProvider
