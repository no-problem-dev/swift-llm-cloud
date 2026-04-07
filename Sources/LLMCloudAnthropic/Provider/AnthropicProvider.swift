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

    /// 構造化出力のベータヘッダー
    private static let structuredOutputsBeta = "structured-outputs-2025-11-13"

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
        let effectiveBaseURL = baseURL ?? URL(string: "https://api.anthropic.com")!

        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            session: session,
            authTokenProvider: StaticTokenProvider(token: apiKey),
            keyDecodingStrategy: .convertFromSnakeCase
        )
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

        // ベータヘッダーの判定
        let beta: String? = request.responseSchema != nil ? Self.structuredOutputsBeta : nil

        // APIContract エンドポイント経由で実行
        let endpoint = AnthropicAPI.CreateMessage(beta: beta, request: body)

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
            throw mapAPIError(error)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    // MARK: - Request Building

    /// LLMRequest を AnthropicRequestBody に変換
    private func buildRequestBody(from request: LLMRequest) throws -> AnthropicRequestBody {
        let messages = try request.messages.map { message in
            try convertToAnthropicMessage(message)
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

        let effectiveSystemPrompt = buildEffectiveSystemPrompt(
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

    /// システムプロンプトと制約プロンプトを統合
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

    /// LLMMessage を Anthropic メッセージ形式に変換
    private func convertToAnthropicMessage(_ message: LLMMessage) throws -> AnthropicMessage {
        let role = message.role == .user ? "user" : "assistant"
        var contentBlocks: [AnthropicMessageContent] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                contentBlocks.append(.text(text))
            case .toolUse(let id, let name, let input):
                contentBlocks.append(.toolUse(id: id, name: name, input: input))
            case .toolResult(let toolCallId, _, let resultContent):
                contentBlocks.append(.toolResult(toolUseId: toolCallId, content: resultContent.contentValue, isError: resultContent.isError))
            case .image(let imageContent):
                contentBlocks.append(.image(imageContent))
            case .audio:
                throw LLMError.mediaNotSupported(mediaType: "audio", provider: "Anthropic")
            case .video:
                throw LLMError.mediaNotSupported(mediaType: "video", provider: "Anthropic")
            case .thinking:
                break
            }
        }

        return AnthropicMessage(role: role, content: contentBlocks)
    }

    // MARK: - Response Conversion

    /// AnthropicResponseBody を LLMResponse に変換
    private func convertToLLMResponse(_ response: AnthropicResponseBody) throws -> LLMResponse {
        let stopReason = response.stopReason.flatMap { LLMResponse.StopReason(rawValue: $0) }

        let contentBlocks = try response.content.compactMap { block -> LLMResponse.ContentBlock? in
            switch block.type {
            case "text":
                return block.text.map { .text($0) }
            case "tool_use":
                guard let id = block.id, let name = block.name, let input = block.input else {
                    return nil
                }
                let inputData = try JSONEncoder().encode(input)
                return .toolUse(id: id, name: name, input: inputData)
            default:
                return nil
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        return LLMResponse(
            content: contentBlocks,
            model: response.model,
            usage: TokenUsage(
                inputTokens: response.usage.inputTokens,
                outputTokens: response.usage.outputTokens,
                cacheCreationTokens: response.usage.cacheCreationInputTokens,
                cacheReadTokens: response.usage.cacheReadInputTokens
            ),
            stopReason: stopReason
        )
    }

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
