import LLMCloudClient
import LLMClient
// OpenAIClient+SpeechGeneration.swift
// swift-llm-structured-outputs
//
// Text-to-speech for the OpenAI client.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + SpeechGenerationCapable

extension OpenAIClient: SpeechGenerationCapable {
    public typealias SpeechModel = OpenAITTSModel
    public typealias Voice = OpenAIVoice

    /// Speaks the given text.
    ///
    /// This endpoint answers with the encoded audio itself rather than JSON, so the bytes are
    /// taken from the raw body. The transcript on the result is the text that was submitted, not
    /// a transcription of the audio.
    ///
    /// - Parameters:
    ///   - input: Text to speak. OpenAI caps a single request at 4096 characters.
    ///   - model: Text-to-speech model to run.
    ///   - voice: Voice to speak in.
    ///   - speed: Playback rate from 0.25 to 4.0. Defaults to 1.0.
    ///   - format: Audio encoding. Defaults to MP3.
    /// - Throws: `SpeechGenerationError` when the text is empty or too long, the speed is out
    ///   of range, or the model does not offer the requested format. All four are checked before
    ///   the request goes out.
    public func generateSpeech(
        input: LLMInput,
        model: OpenAITTSModel,
        voice: OpenAIVoice,
        speed: Double?,
        format: AudioOutputFormat?
    ) async throws -> GeneratedAudio {
        let text = input.prompt.render()

        // Validate locally so an impossible request never reaches the API.
        if text.isEmpty {
            throw SpeechGenerationError.emptyText
        }

        if text.count > 4096 {
            throw SpeechGenerationError.textTooLong(length: text.count, maximum: 4096)
        }

        let actualSpeed = speed ?? 1.0
        if actualSpeed < 0.25 || actualSpeed > 4.0 {
            throw SpeechGenerationError.invalidSpeed(actualSpeed)
        }

        let actualFormat = format ?? .mp3
        if !model.supportedFormats.contains(actualFormat) {
            throw SpeechGenerationError.unsupportedFormat(actualFormat, model: model.displayName)
        }

        let body = OpenAITTSRequestBody(
            model: model.id,
            input: text,
            voice: voice.id,
            responseFormat: actualFormat.fileExtension,
            speed: actualSpeed
        )

        let data = try await mediaClient.executeRaw(
            OpenAIMediaAPI.CreateSpeech(customHeaders: [:], request: body)
        ).output

        return GeneratedAudio(
            data: data,
            format: actualFormat,
            transcript: text
        )
    }
}
