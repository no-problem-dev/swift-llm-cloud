import LLMCloudClient
import LLMClient
// GeminiClient+ImageGeneration.swift
// swift-llm-structured-outputs
//
// Gemini クライアントの画像生成機能拡張
// Imagen モデルと Gemini Image モデルの両方をサポート

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient + ImageGenerationCapable

extension GeminiClient: ImageGenerationCapable {
    public typealias ImageModel = GeminiImageModel

    /// 画像を生成
    ///
    /// - Parameters:
    ///   - input: LLM 入力（プロンプトテキスト）
    ///   - model: 使用する画像生成モデル
    ///   - size: 出力画像のサイズ
    ///   - quality: 画像品質（Gemini では未使用）
    ///   - format: 出力フォーマット（Gemini は PNG のみ対応）
    ///   - n: 生成する画像の数
    /// - Returns: 生成された画像
    public func generateImage(
        input: LLMInput,
        model: GeminiImageModel,
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
    ///   - quality: 画像品質（Gemini では未使用）
    ///   - format: 出力フォーマット（Gemini は PNG のみ対応）
    ///   - n: 生成する画像の数
    /// - Returns: 生成された画像の配列
    public func generateImages(
        input: LLMInput,
        model: GeminiImageModel,
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

        // Gemini は PNG のみ対応
        let actualFormat: ImageOutputFormat = .png
        if let requestedFormat = format, requestedFormat != .png {
            throw ImageGenerationError.unsupportedFormat(requestedFormat, model: model.displayName)
        }

        // モデルタイプに応じて処理を分岐
        if model.isImagenModel {
            return try await generateWithImagen(
                prompt: prompt,
                model: model,
                size: actualSize,
                n: n,
                format: actualFormat
            )
        } else {
            return try await generateWithGeminiImage(
                prompt: prompt,
                model: model,
                format: actualFormat
            )
        }
    }

    // MARK: - Imagen API

    private func generateWithImagen(
        prompt: String,
        model: GeminiImageModel,
        size: ImageSize,
        n: Int,
        format: ImageOutputFormat
    ) async throws -> [GeneratedImage] {
        let body = ImagenRequestBody(
            instances: [.init(prompt: prompt)],
            parameters: .init(
                sampleCount: n,
                aspectRatio: aspectRatioString(for: size),
                personGeneration: "allow_adult"
            )
        )
        let response = try await mediaClient.executeWithResponse(
            GeminiMediaAPI.ImagenPredict(modelId: model.id, request: body)
        ).output

        return try response.predictions.compactMap { prediction -> GeneratedImage? in
            guard let base64 = prediction.bytesBase64Encoded else { return nil }
            guard let imageData = Data(base64Encoded: base64) else {
                throw GeneratedMediaError.invalidBase64Data
            }
            return GeneratedImage(data: imageData, format: format, revisedPrompt: nil)
        }
    }

    // MARK: - Gemini Image API (generateContent)

    private func generateWithGeminiImage(
        prompt: String,
        model: GeminiImageModel,
        format: ImageOutputFormat
    ) async throws -> [GeneratedImage] {
        let body = GeminiImageRequestBody(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(responseModalities: ["TEXT", "IMAGE"])
        )
        let response = try await mediaClient.executeWithResponse(
            GeminiMediaAPI.GenerateImageContent(modelId: model.id, request: body)
        ).output

        var images: [GeneratedImage] = []
        for candidate in response.candidates ?? [] {
            for part in candidate.content?.parts ?? [] {
                if let base64 = part.inlineData?.data, let imageData = Data(base64Encoded: base64) {
                    images.append(GeneratedImage(data: imageData, format: format, revisedPrompt: nil))
                }
            }
        }
        if images.isEmpty { throw LLMError.emptyResponse }
        return images
    }

    // MARK: - Private Helpers

    private func aspectRatioString(for size: ImageSize) -> String {
        switch size {
        case .square256, .square512, .square1024:
            return "1:1"
        case .landscape1792x1024, .landscape1536x1024:
            return "16:9"
        case .portrait1024x1792, .portrait1024x1536:
            return "9:16"
        }
    }

}
