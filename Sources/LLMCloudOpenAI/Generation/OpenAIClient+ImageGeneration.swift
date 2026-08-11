import LLMCloudClient
import LLMClient
// OpenAIClient+ImageGeneration.swift
// swift-llm-structured-outputs
//
// Image generation for the OpenAI client.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + ImageGenerationCapable

extension OpenAIClient: ImageGenerationCapable {
    public typealias ImageModel = OpenAIImageModel

    /// Generates a single image.
    ///
    /// - Parameters:
    ///   - input: Prompt describing the image.
    ///   - model: Image model to run.
    ///   - options: Size defaults to 1024×1024 and one the model does not offer is rejected before
    ///     the request goes out; quality is forwarded as given and is not checked against the
    ///     model, so a tier the model does not offer is rejected by the API rather than here;
    ///     format defaults to PNG; and `n` is forced to 1 here.
    /// - Throws: `LLMError.emptyResponse` if the API answers with no image at all.
    public func generateImage(
        input: LLMInput,
        model: OpenAIImageModel,
        options: ImageGenerationOptions
    ) async throws -> GeneratedImage {
        var single = options
        single.n = 1
        let images = try await generateImages(input: input, model: model, options: single)
        guard let image = images.first else {
            throw LLMError.emptyResponse
        }
        return image
    }

    /// Generates several images from one prompt.
    ///
    /// Size, format, and count are validated locally first, so an unsupported combination fails
    /// without spending a request. Images that OpenAI returns as links are downloaded in
    /// parallel, which means the returned array is not in the order the API listed them.
    ///
    /// - Parameters:
    ///   - input: Prompt describing the images.
    ///   - model: Image model to run.
    ///   - options: Size defaults to 1024×1024; quality is forwarded as given and is not checked
    ///     against the model, so a tier the model does not offer is rejected by the API rather
    ///     than here; format defaults to PNG; and `n` is capped by the model's own limit.
    /// - Throws: `ImageGenerationError` when the count, size, or format exceeds what the model
    ///   accepts, or `GeneratedMediaError` when a returned image can be neither decoded nor
    ///   downloaded.
    public func generateImages(
        input: LLMInput,
        model: OpenAIImageModel,
        options: ImageGenerationOptions
    ) async throws -> [GeneratedImage] {
        let prompt = input.prompt.render()
        // Validate locally so an impossible request never reaches the API.
        if options.n > model.maxImages {
            throw ImageGenerationError.exceedsMaxImages(requested: options.n, maximum: model.maxImages)
        }

        let actualSize = options.size ?? .square1024
        if !model.supportedSizes.contains(actualSize) {
            throw ImageGenerationError.unsupportedSize(actualSize, model: model.displayName)
        }

        let actualFormat = options.format ?? .png
        if !MediaCompatibility.isSupported(actualFormat, by: .openai) {
            throw ImageGenerationError.unsupportedFormat(actualFormat, model: model.displayName)
        }

        // GPT-Image rejects response_format and always answers with base64. Only DALL·E
        // has to be told which of the two encodings to use.
        let useResponseFormat = model == .dalle2 || model == .dalle3

        let request = OpenAIImageRequestBody(
            model: model.id,
            prompt: prompt,
            n: options.n,
            size: actualSize.rawValue,
            quality: options.quality?.rawValue,
            responseFormat: useResponseFormat ? "b64_json" : nil,
            outputFormat: actualFormat == .png ? nil : actualFormat.fileExtension
        )

        let response = try await mediaClient.executeWithResponse(
            OpenAIMediaAPI.GenerateImage(customHeaders: [:], request: request)
        ).output

        // Inline images decode immediately; linked ones still have to be fetched.
        return try await withThrowingTaskGroup(of: GeneratedImage.self) { group in
            for item in response.data {
                group.addTask {
                    let imageData: Data

                    if let b64Json = item.b64Json {
                        guard let data = Data(base64Encoded: b64Json) else {
                            throw GeneratedMediaError.invalidBase64Data
                        }
                        imageData = data
                    } else if let urlString = item.url, let imageURL = URL(string: urlString) {
                        // The link expires, so download it now. This uses the shared session
                        // rather than the one configured on the client.
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
