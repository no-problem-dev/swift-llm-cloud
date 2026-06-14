import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicProvider

/// Anthropic Claude API プロバイダー（内部実装）
///
/// APIClient + APIContract を使用して Anthropic Messages API を呼び出す。
/// このプロバイダーは `AnthropicClient` 内部で使用されます。
internal struct AnthropicProvider: LLMProvider, RetryableProviderProtocol {
    /// APIClient
    private let apiClient: APIClientImpl

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API キー
    ///   - baseURL: カスタムベースURL（オプション）
    ///   - session: カスタム URLSession（オプション）
    init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.init(transport: URLSessionTransport(session: session), apiKey: apiKey, baseURL: baseURL)
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        baseURL: URL? = nil
    ) {
        let effectiveBaseURL = baseURL ?? URL(string: "https://api.anthropic.com")!
        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyStyle: .snakeCase
        )
    }

    /// ストリーミング(stream: true)ボディを contract 経由で送信し、生の SSEEvent を流す。
    /// イベント解釈はプロバイダ側の accumulator が行う。
    func streamMessageEvents(_ body: AnthropicRequestBody, beta: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        apiClient.executeEventStream(AnthropicAPI.CreateMessage(beta: beta, request: body))
    }

    /// 構築済みボディを contract 経由で送信する（tools/structured output 等、send で
    /// 表現できないリクエストはこちらを使う）。
    func sendBody(_ body: AnthropicRequestBody, beta: String?) async throws -> (AnthropicResponseBody, Int, [String: String]) {
        let endpoint = AnthropicAPI.CreateMessage(beta: beta, request: body)
        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)
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

    // MARK: - LLMProvider

    func send(_ request: LLMRequest) async throws -> LLMResponse {
        let (response, _) = try await sendWithResponse(request)
        return response
    }

    // MARK: - RetryableProviderProtocol

    func sendWithResponse(_ request: LLMRequest) async throws -> (LLMResponse, HTTPURLResponse) {
        // モデルの検証
        guard case .claude = request.model else {
            throw LLMError.modelNotSupported(model: request.model.id, provider: "Anthropic")
        }

        // リクエストボディを構築
        let body = try buildRequestBody(from: request)

        // 構造化出力は GA（output_config.format）。beta ヘッダーは不要。
        let endpoint = AnthropicAPI.CreateMessage(beta: nil, request: body)

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)

            // APIResponse から HTTPURLResponse 相当の情報を構成
            let llmResponse = try convertToLLMResponse(apiResponse.output)

            // HTTPURLResponse を構成（RetryableProvider 互換）
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
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
            throw mapAPIErrorToLLMError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    // MARK: - Request Building

    /// LLMRequest を AnthropicRequestBody に変換
    private func buildRequestBody(from request: LLMRequest) throws -> AnthropicRequestBody {
        let messages = try request.messages.map { message in
            try AnthropicMessageConverter.convert(message)
        }

        var outputFormat: AnthropicOutputFormat?
        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = AnthropicSchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            outputFormat = AnthropicOutputFormat(
                type: "json_schema",
                schema: adaptationResult.schema
            )

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        let effectiveSystemPrompt = composeSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        return AnthropicRequestBody(
            model: request.model.id,
            messages: messages,
            system: effectiveSystemPrompt,
            maxTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: request.temperature,
            outputConfig: outputFormat.map { AnthropicOutputConfig(format: $0) }
        )
    }

    // MARK: - Response Conversion

    /// AnthropicResponseBody を LLMResponse に変換
    private func convertToLLMResponse(_ response: AnthropicResponseBody) throws -> LLMResponse {
        let stopReason = response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        let contentBlocks = try response.content.compactMap { block -> LLMResponse.ContentBlock? in
            switch AnthropicBlockType(rawValue: block.type) {
            case .text:
                return block.text.map { .text($0) }
            case .toolUse:
                guard let id = block.id, let name = block.name, let input = block.input else {
                    return nil
                }
                let inputData = try JSONEncoder().encode(input)
                return .toolUse(id: id, name: name, input: inputData)
            case .thinking, nil:
                return nil
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: AnthropicUsageNormalizer.normalize(response.usage),
            stopReason: stopReason
        )
    }

    /// APIError を LLMError にマッピング
}

// MARK: - Static Token Provider

/// 固定トークンを提供する AuthTokenProvider
