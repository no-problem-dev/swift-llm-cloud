import LLMClient
import LLMCloudClient
import APIClient
import APIContract
import Foundation
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
        let effectiveBaseURL = URL(string: baseURL ?? "https://generativelanguage.googleapis.com/v1beta/models")!

        self.apiClient = APIClientImpl(
            baseURL: effectiveBaseURL,
            session: session,
            authTokenProvider: StaticTokenProvider(token: apiKey)
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
            throw mapAPIError(error)
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
            contents.append(contentsOf: convertToGeminiContents(message))
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
        let effectiveSystemPrompt = buildEffectiveSystemPrompt(
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
                    let argsDict = functionCall.args?.mapValues { $0.toAny() } ?? [:]
                    if let argsData = try? JSONSerialization.data(withJSONObject: argsDict) {
                        contentBlocks.append(.toolUse(
                            id: UUID().uuidString,
                            name: functionCall.name,
                            input: argsData
                        ))
                    }
                }
            }
        }

        guard !contentBlocks.isEmpty || stopReason == .toolUse else {
            throw LLMError.emptyResponse
        }

        // 使用量を取得
        let usage: TokenUsage
        if let usageMetadata = response.usageMetadata {
            usage = TokenUsage(
                inputTokens: usageMetadata.promptTokenCount ?? 0,
                outputTokens: usageMetadata.candidatesTokenCount ?? 0,
                cacheReadTokens: usageMetadata.cachedContentTokenCount,
                reasoningTokens: usageMetadata.thoughtsTokenCount
            )
        } else {
            usage = TokenUsage(inputTokens: 0, outputTokens: 0)
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

    /// LLMMessage を Gemini コンテンツ形式に変換
    private func convertToGeminiContents(_ message: LLMMessage) -> [GeminiContent] {
        let role = message.role == .user ? "user" : "model"
        var parts: [GeminiPart] = []
        var toolResultParts: [GeminiPart] = []

        for content in message.contents {
            switch content {
            case .text(let text):
                parts.append(GeminiPart(text: text))

            case .toolUse(_, let name, let input):
                let args: [String: Any]?
                if let argsDict = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
                    args = argsDict
                } else {
                    args = nil
                }
                let functionCall = GeminiFunctionCall(name: name, args: args)
                parts.append(GeminiPart(functionCall: functionCall))

            case .toolResult(_, let name, let content):
                let responseDict: [String: Any] = ["result": content.contentValue]
                let functionResponse = GeminiFunctionResponse(name: name, response: responseDict)
                toolResultParts.append(GeminiPart(functionResponse: functionResponse))

            case .image(let imageContent):
                if let geminiPart = convertMediaToGeminiPart(source: imageContent.source, mimeType: imageContent.mediaType) {
                    parts.append(geminiPart)
                }

            case .audio(let audioContent):
                if let geminiPart = convertMediaToGeminiPart(source: audioContent.source, mimeType: audioContent.mediaType) {
                    parts.append(geminiPart)
                }

            case .video(let videoContent):
                if let geminiPart = convertMediaToGeminiPart(source: videoContent.source, mimeType: videoContent.mediaType) {
                    parts.append(geminiPart)
                }

            case .thinking:
                break
            }
        }

        var contents: [GeminiContent] = []

        if !parts.isEmpty {
            contents.append(GeminiContent(role: role, parts: parts))
        }

        if !toolResultParts.isEmpty {
            contents.append(GeminiContent(role: "user", parts: toolResultParts))
        }

        return contents
    }

    /// メディアソースをGeminiパーツに変換
    private func convertMediaToGeminiPart<T: MediaType>(source: MediaSource, mimeType: T) -> GeminiPart? {
        switch source {
        case .base64(let data):
            let base64String = data.base64EncodedString()
            let inlineData = GeminiInlineData(mimeType: mimeType.mimeType, data: base64String)
            return GeminiPart(inlineData: inlineData)

        case .url(let url):
            let fileData = GeminiFileData(mimeType: mimeType.mimeType, fileUri: url.absoluteString)
            return GeminiPart(fileData: fileData)

        case .fileReference(let id):
            let fileData = GeminiFileData(mimeType: mimeType.mimeType, fileUri: id)
            return GeminiPart(fileData: fileData)
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
