import LLMCloudClient
import LLMClient
// GeminiClient+ImageGeneration.swift
// swift-llm-structured-outputs
//
// Image generation for both Imagen models and Gemini image models, which use different
// endpoints and response shapes.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient + ImageGenerationCapable

extension GeminiClient: ImageGenerationCapable {
    public typealias ImageModel = GeminiImageModel

    /// Generates a single image.
    ///
    /// - Parameters:
    ///   - input: Prompt; only its text is used, as neither image endpoint accepts attachments.
    ///   - model: Image model, which decides whether the Imagen or Gemini endpoint is called.
    ///   - size: Output size, defaulting to 1024 square. Sent to Imagen as an aspect ratio, since
    ///     that is all Imagen takes.
    ///   - quality: Ignored; Gemini exposes no quality setting.
    ///   - format: Must be PNG, the only format either endpoint returns.
    ///   - n: Ignored here; exactly one image is returned.
    /// - Throws: `LLMError.emptyResponse` when the model returned no image at all.
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

    /// Generates several images from one prompt.
    ///
    /// Imagen models produce up to `n` images in one `:predict` call. Gemini image models generate
    /// through `:generateContent` instead, which takes no sample count, so they return whatever
    /// image parts the response happens to contain regardless of `n`.
    ///
    /// - Parameters:
    ///   - input: Prompt; only its text is used.
    ///   - model: Image model, which decides which endpoint is called.
    ///   - size: Output size, defaulting to 1024 square. Imagen receives it as an aspect ratio.
    ///   - quality: Ignored; Gemini exposes no quality setting.
    ///   - format: Must be PNG, the only format either endpoint returns.
    ///   - n: Number of images requested, honoured only by Imagen models.
    /// - Throws: `ImageGenerationError` when `n` is above the model's limit or the size or format
    ///   is unsupported, and `GeneratedMediaError.invalidBase64Data` when a returned image cannot
    ///   be decoded.
    public func generateImages(
        input: LLMInput,
        model: GeminiImageModel,
        size: ImageSize?,
        quality: ImageQuality?,
        format: ImageOutputFormat?,
        n: Int
    ) async throws -> [GeneratedImage] {
        let prompt = input.prompt.render()
        // Reject what the model cannot do before spending a request on it.
        if n > model.maxImages {
            throw ImageGenerationError.exceedsMaxImages(requested: n, maximum: model.maxImages)
        }

        let actualSize = size ?? .square1024
        if !model.supportedSizes.contains(actualSize) {
            throw ImageGenerationError.unsupportedSize(actualSize, model: model.displayName)
        }

        // Both endpoints return PNG and nothing else.
        let actualFormat: ImageOutputFormat = .png
        if let requestedFormat = format, requestedFormat != .png {
            throw ImageGenerationError.unsupportedFormat(requestedFormat, model: model.displayName)
        }

        // Imagen and Gemini image models speak different endpoints.
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

    /// Generates through Imagen's predict endpoint, which returns base64 images directly.
    ///
    /// Imagen takes an aspect ratio rather than pixel dimensions, and a sample count for batching.
    /// Person generation is requested at the adult-only setting.
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

    /// Generates through a Gemini image model, which answers on the ordinary generation endpoint.
    ///
    /// The request asks for text and image response modalities and the images come back as inline
    /// base64 parts of the candidates. There is no way to ask for a specific count or size here,
    /// and any text part is discarded.
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
