import LLMCloudClient
import LLMClient
// OpenAIClient+ImageGeneration.swift
// swift-llm-structured-outputs
//
// OpenAI クライアントの画像生成機能拡張

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + ImageGenerationCapable

extension OpenAIClient: ImageGenerationCapable {
    public typealias ImageModel = OpenAIImageModel

    /// 画像を生成
    ///
    /// - Parameters:
    ///   - input: LLM 入力（プロンプトテキスト）
    ///   - model: 使用する画像生成モデル
    ///   - size: 出力画像のサイズ
    ///   - quality: 画像品質
    ///   - format: 出力フォーマット
    ///   - n: 生成する画像の数
    /// - Returns: 生成された画像
    public func generateImage(
        input: LLMInput,
        model: OpenAIImageModel,
        size: ImageSize?,
        quality: ImageQuality?,
        format: ImageOutputFormat?,
        n: Int
    ) async throws -> GeneratedImage {
        let images = try await generateImages(
            input: input,
            model: model,
            size: size,
            quality: quality,
            format: format,
            n: 1
        )
        guard let image = images.first else {
            throw LLMError.emptyResponse
        }
        return image
    }

    /// 複数の画像を生成
    ///
    /// - Parameters:
    ///   - input: LLM 入力（プロンプトテキスト）
    ///   - model: 使用する画像生成モデル
    ///   - size: 出力画像のサイズ
    ///   - quality: 画像品質
    ///   - format: 出力フォーマット
    ///   - n: 生成する画像の数
    /// - Returns: 生成された画像の配列
    public func generateImages(
        input: LLMInput,
        model: OpenAIImageModel,
        size: ImageSize?,
        quality: ImageQuality?,
        format: ImageOutputFormat?,
        n: Int
    ) async throws -> [GeneratedImage] {
        // プロンプトテキストを取得
        let prompt = input.prompt.render()
        // バリデーション
        if n > model.maxImages {
            throw ImageGenerationError.exceedsMaxImages(requested: n, maximum: model.maxImages)
        }

        let actualSize = size ?? .square1024
        if !model.supportedSizes.contains(actualSize) {
            throw ImageGenerationError.unsupportedSize(actualSize, model: model.displayName)
        }

        let actualFormat = format ?? .png
        if !MediaCompatibility.isSupported(actualFormat, by: .openai) {
            throw ImageGenerationError.unsupportedFormat(actualFormat, model: model.displayName)
        }

        // GPT-Image は response_format 非対応（常に base64）。DALL-E のみ response_format を使う。
        let useResponseFormat = model == .dalle2 || model == .dalle3

        let request = OpenAIImageRequestBody(
            model: model.id,
            prompt: prompt,
            n: n,
            size: actualSize.rawValue,
            quality: quality?.rawValue,
            responseFormat: useResponseFormat ? "b64_json" : nil,
            outputFormat: actualFormat == .png ? nil : actualFormat.fileExtension
        )

        let response = try await mediaClient.executeWithResponse(
            OpenAIMediaAPI.GenerateImage(customHeaders: [:], request: request)
        ).output

        // レスポンス変換
        return try await withThrowingTaskGroup(of: GeneratedImage.self) { group in
            for item in response.data {
                group.addTask {
                    let imageData: Data

                    if let b64Json = item.b64Json {
                        // Base64データがある場合
                        guard let data = Data(base64Encoded: b64Json) else {
                            throw GeneratedMediaError.invalidBase64Data
                        }
                        imageData = data
                    } else if let urlString = item.url, let imageURL = URL(string: urlString) {
                        // URLがある場合はダウンロード
                        let (data, _) = try await URLSession.shared.data(from: imageURL)
                        imageData = data
                    } else {
                        throw GeneratedMediaError.invalidImageData
                    }

                    return GeneratedImage(
                        data: imageData,
                        format: actualFormat,
                        revisedPrompt: item.revisedPrompt
                    )
                }
            }

            var images: [GeneratedImage] = []
            for try await image in group {
                images.append(image)
            }
            return images
        }
    }
}
