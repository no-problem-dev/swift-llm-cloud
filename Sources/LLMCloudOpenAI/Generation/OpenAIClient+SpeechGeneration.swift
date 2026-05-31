import LLMCloudClient
import LLMClient
// OpenAIClient+SpeechGeneration.swift
// swift-llm-structured-outputs
//
// OpenAI クライアントの音声生成（TTS）機能拡張

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + SpeechGenerationCapable

extension OpenAIClient: SpeechGenerationCapable {
    public typealias SpeechModel = OpenAITTSModel
    public typealias Voice = OpenAIVoice

    /// 入力から音声を生成
    ///
    /// - Parameters:
    ///   - input: LLM 入力（音声化するテキスト、最大 4096 文字）
    ///   - model: 使用する TTS モデル
    ///   - voice: 使用する声
    ///   - speed: 再生速度（0.25〜4.0、デフォルト: 1.0）
    ///   - format: 出力フォーマット（デフォルト: mp3）
    /// - Returns: 生成された音声
    public func generateSpeech(
        input: LLMInput,
        model: OpenAITTSModel,
        voice: OpenAIVoice,
        speed: Double?,
        format: AudioOutputFormat?
    ) async throws -> GeneratedAudio {
        // テキストを取得
        let text = input.prompt.render()

        // バリデーション
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
