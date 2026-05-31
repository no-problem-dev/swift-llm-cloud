import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
import StructuredDataCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiProvider

/// Google Gemini API プロバイダー（内部実装）
///
/// APIClient + APIContract を使用して Gemini API を呼び出す。
/// このプロバイダーは `GeminiClient` 内部で使用されます。
internal struct GeminiProvider: LLMProvider, RetryableProviderProtocol {
    /// APIClient
    private let apiClient: APIClientImpl

    /// デフォルトの最大トークン数
    private static let defaultMaxTokens = 4096

    // MARK: - Initializers

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: Google AI API キー
    ///   - baseURL: カスタムベース URL（オプション）
    ///   - session: カスタム URLSession（オプション）
    init(
        apiKey: String,
        baseURL: String? = nil,
        session: URLSession = .shared
    ) {
        self.init(transport: URLSessionTransport(session: session), apiKey: apiKey, baseURL: baseURL)
    }

    init(
        transport: any HTTPTransport & HTTPStreamingTransport,
        apiKey: String,
        baseURL: String? = nil
    ) {
        let effectiveBaseURL = URL(string: baseURL ?? "https://generativelanguage.googleapis.com/v1beta/models")!
        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            transport: transport,
            authTokenProvider: StaticTokenProvider(token: apiKey)
        )
    }

    /// ストリーミング生成の生 SSEEvent を流す。テキスト抽出は呼び出し側で行う。
    func streamContentEvents(_ body: GeminiRequestBody, modelId: String) -> AsyncThrowingStream<SSEEvent, Error> {
        apiClient.executeEventStream(GeminiAPI.StreamGenerateContent(modelId: modelId, request: body))
    }

    /// 構築済みボディを contract 経由で送信する。
    func sendBody(_ body: GeminiRequestBody, modelId: String) async throws -> (GeminiResponseBody, Int, [String: String]) {
        let endpoint = GeminiAPI.GenerateContent(modelId: modelId, request: body)
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
        guard case .gemini = request.model else {
            throw LLMError.modelNotSupported(model: request.model.id, provider: "Gemini")
        }

        // リクエストボディを構築
        let body = try buildRequestBody(from: request)

        // APIContract エンドポイント経由で実行
        let endpoint = GeminiAPI.GenerateContent(
            modelId: request.model.id,
            request: body
        )

        do {
            let apiResponse = try await apiClient.executeWithResponse(endpoint)

            // LLMResponse に変換
            let llmResponse = try convertToLLMResponse(apiResponse.output, model: request.model.id)

            // HTTPURLResponse を構成（RetryableProvider 互換）
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
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

    /// リクエストボディを構築
    private func buildRequestBody(from request: LLMRequest) throws -> GeminiRequestBody {
        // コンテンツを構築
        var contents: [GeminiContent] = []

        for message in request.messages {
            contents.append(contentsOf: GeminiContentConverter.convert(message))
        }

        // 生成設定
        var generationConfig = GeminiGenerationConfig(
            maxOutputTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: request.temperature
        )

        // 構造化出力の設定と制約プロンプトの生成
        var constraintPrompt: SystemPrompt?

        if let schema = request.responseSchema {
            let adapter = GeminiSchemaAdapter()
            let adaptationResult = adapter.adaptWithConstraints(schema, fieldPath: "")

            generationConfig.responseMimeType = "application/json"
            generationConfig.responseSchema = adaptationResult.schema

            constraintPrompt = adaptationResult.toConstraintSystemPrompt()
        }

        // システムインストラクションを構築（制約プロンプトを統合）
        let effectiveSystemPrompt = composeSystemPrompt(
            base: request.systemPrompt,
            constraints: constraintPrompt
        )

        var systemInstruction: GeminiContent?
        if let systemPrompt = effectiveSystemPrompt {
            systemInstruction = GeminiContent(
                role: "user",
                parts: [GeminiPart(text: systemPrompt)]
            )
        }

        return GeminiRequestBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            tools: nil,
            toolConfig: nil
        )
    }

    /// システムプロンプトと制約プロンプトを統合

    // MARK: - Response Conversion

    /// GeminiResponseBody を LLMResponse に変換
    private func convertToLLMResponse(_ response: GeminiResponseBody, model: String) throws -> LLMResponse {
        // 最初の候補を取得
        guard let candidate = response.candidates?.first else {
            if let promptFeedback = response.promptFeedback,
               let blockReason = promptFeedback.blockReason {
                throw LLMError.contentBlocked(reason: blockReason)
            }
            throw LLMError.emptyResponse
        }

        // 停止理由をマッピング
        let stopReason = mapStopReason(candidate.finishReason)

        // コンテンツブロックを構築
        var contentBlocks: [LLMResponse.ContentBlock] = []

        if let content = candidate.content {
            for part in content.parts {
                if let text = part.text {
                    contentBlocks.append(.text(text))
                }
                if let functionCall = part.functionCall {
                    let argsData = (functionCall.args.flatMap { try? JSONEncoder().encode($0) }) ?? Data("{}".utf8)
                    contentBlocks.append(.toolUse(
                        id: UUID().uuidString,
                        name: functionCall.name,
                        input: argsData
                    ))
                }
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        // 使用量を取得
        let usage: TokenUsage
        if let usageMetadata = response.usageMetadata {
            usage = GeminiUsageNormalizer.normalize(usageMetadata)
        } else {
            usage = TokenUsage.zero
        }

        return LLMResponse(
            content: contentBlocks,
            model: model,
            usage: usage,
            stopReason: stopReason
        )
    }

    /// 停止理由をマッピング
    private func mapStopReason(_ reason: String?) -> LLMResponse.StopReason? {
        guard let reason = reason else { return nil }
        switch reason {
        case "STOP":
            return .endTurn
        case "MAX_TOKENS":
            return .maxTokens
        case "SAFETY":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Error Mapping

    /// APIError を LLMError にマッピング
}

// MARK: - Static Token Provider

/// 固定トークンを提供する AuthTokenProvider
