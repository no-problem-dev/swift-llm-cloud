import LLMCloudClient
import LLMClient
// OpenAIClient+VideoGeneration.swift
// swift-llm-structured-outputs
//
// OpenAI クライアントの動画生成機能拡張（Sora 2）

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + VideoGenerationCapable

extension OpenAIClient: VideoGenerationCapable {
    public typealias VideoModel = OpenAIVideoModel

    /// 動画生成ジョブを開始
    ///
    /// Sora 2 API を使用して動画生成を開始します。
    /// 動画生成は非同期で処理されるため、ジョブ ID を返します。
    ///
    /// ## 使用例
    /// ```swift
    /// let client = OpenAIClient(apiKey: "sk-...")
    /// let job = try await client.startVideoGeneration(
    ///     input: "A cat playing piano on stage",
    ///     model: .sora2
    /// )
    /// ```
    public func startVideoGeneration(
        input: LLMInput,
        model: OpenAIVideoModel,
        duration: Int?,
        aspectRatio: VideoAspectRatio?,
        resolution: VideoResolution?
    ) async throws -> VideoGenerationJob {
        // プロンプトテキストを取得
        let prompt = input.prompt.render()
        // バリデーション
        let actualDuration = duration ?? 4
        if !model.supportedDurations.contains(actualDuration) {
            throw VideoGenerationError.durationExceedsLimit(
                requested: actualDuration,
                maximum: model.maxDuration
            )
        }

        let actualAspectRatio = aspectRatio ?? .landscape16x9
        if !model.supportedAspectRatios.contains(actualAspectRatio) {
            throw VideoGenerationError.unsupportedAspectRatio(actualAspectRatio, model: model.displayName)
        }

        let actualResolution = resolution ?? model.defaultResolution
        if !model.supportedResolutions.contains(actualResolution) {
            throw VideoGenerationError.unsupportedResolution(actualResolution, model: model.displayName)
        }

        let sizeString = soraSize(for: actualAspectRatio, resolution: actualResolution)

        let body = SoraVideoRequestBody(
            model: model.id, prompt: prompt, seconds: String(actualDuration), size: sizeString
        )
        let response = try await mediaClient.executeWithResponse(
            OpenAIMediaAPI.CreateVideo(request: body)
        ).output

        // 設定を作成
        let configuration = VideoGenerationConfiguration(
            duration: actualDuration,
            resolution: actualResolution,
            frameRate: nil,
            aspectRatio: actualAspectRatio,
            format: .mp4
        )

        return VideoGenerationJob(
            id: response.id,
            status: mapStatus(response.status),
            prompt: prompt,
            configuration: configuration,
            createdAt: Date(timeIntervalSince1970: TimeInterval(response.createdAt))
        )
    }

    /// 動画生成ジョブのステータスを確認
    public func checkVideoStatus(_ job: VideoGenerationJob) async throws -> VideoGenerationJob {
        let statusResponse = try await mediaClient.executeWithResponse(
            OpenAIMediaAPI.GetVideoStatus(videoId: job.id)
        ).output

        let status = mapStatus(statusResponse.status)
        var videoURL: URL?
        var errorMessage: String?

        if status == .completed {
            // 動画ダウンロード URL を取得
            videoURL = videoDownloadEndpoint(videoId: job.id)
        } else if status == .failed {
            errorMessage = statusResponse.error?.message ?? "Video generation failed"
        }

        return job.updated(
            status: status,
            videoURL: videoURL,
            errorMessage: errorMessage,
            progress: statusResponse.progress.map { Double($0) / 100.0 }
        )
    }

    /// 生成された動画を取得
    public func getGeneratedVideo(_ job: VideoGenerationJob) async throws -> GeneratedVideo {
        guard job.status == .completed else {
            throw VideoGenerationError.jobNotCompleted(status: job.status)
        }

        let data = try await mediaClient.executeRaw(
            OpenAIMediaAPI.DownloadVideo(videoId: job.id)
        ).output

        return GeneratedVideo(
            data: data,
            format: .mp4,
            remoteURL: videoDownloadEndpoint(videoId: job.id),
            duration: job.configuration?.duration.map { TimeInterval($0) },
            resolution: job.configuration?.resolution,
            jobId: job.id,
            prompt: job.prompt
        )
    }

    // MARK: - Private Helpers

    private func videoDownloadEndpoint(videoId: String) -> URL {
        URL(string: "https://api.openai.com/v1/videos/\(videoId)/content")!
    }

    private func soraSize(for aspectRatio: VideoAspectRatio, resolution: VideoResolution) -> String {
        // Sora 2 のサポートサイズ:
        // sora-2: 720x1280, 1280x720
        // sora-2-pro: 720x1280, 1280x720, 1024x1792, 1792x1024
        switch aspectRatio {
        case .landscape16x9:
            switch resolution {
            case .hd720p:
                return "1280x720"
            case .fhd1080p:
                return "1792x1024"
            default:
                return "1280x720"
            }
        case .portrait9x16:
            switch resolution {
            case .hd720p:
                return "720x1280"
            case .fhd1080p:
                return "1024x1792"
            default:
                return "720x1280"
            }
        default:
            // Sora は 16:9 と 9:16 のみサポート
            return "1280x720"
        }
    }

    private func mapStatus(_ status: String) -> VideoGenerationStatus {
        switch status.lowercased() {
        case "queued":
            return .queued
        case "in_progress", "processing":
            return .processing
        case "completed", "succeeded":
            return .completed
        case "failed":
            return .failed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .processing
        }
    }

}
