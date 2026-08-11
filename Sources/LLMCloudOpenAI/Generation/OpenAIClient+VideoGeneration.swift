import LLMCloudClient
import LLMClient
// OpenAIClient+VideoGeneration.swift
// swift-llm-structured-outputs
//
// Video generation for the OpenAI client, on Sora 2.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAIClient + VideoGenerationCapable

extension OpenAIClient: VideoGenerationCapable {
    public typealias VideoModel = OpenAIVideoModel

    /// Starts a video generation job.
    ///
    /// Sora renders asynchronously, so this returns as soon as the job is queued. Poll the job
    /// with ``checkVideoStatus(_:)`` until it completes, then fetch the frames with
    /// ``getGeneratedVideo(_:)``.
    ///
    /// Duration, aspect ratio, and resolution are validated against the model before the request
    /// goes out, and the accepted aspect ratio and resolution are then encoded as the pixel size
    /// Sora expects. Sora renders 16:9 and 9:16 only, so any other aspect ratio is rejected here.
    ///
    /// ## Example
    /// ```swift
    /// let client = OpenAIClient(apiKey: "sk-...")
    /// let job = try await client.startVideoGeneration(
    ///     input: "A cat playing piano on stage",
    ///     model: .sora2
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - input: Prompt describing the clip.
    ///   - model: Sora model to render with.
    ///   - options: Duration, aspect ratio, and resolution. Anything left unset defaults to four
    ///     seconds, 16:9, and the model's own default resolution.
    public func startVideoGeneration(
        input: LLMInput,
        model: OpenAIVideoModel,
        options: VideoGenerationOptions
    ) async throws -> VideoGenerationJob {
        let prompt = input.prompt.render()
        // Validate locally so an impossible request never reaches the API.
        let actualDuration = options.duration ?? 4
        if !model.supportedDurations.contains(actualDuration) {
            throw VideoGenerationError.durationExceedsLimit(
                requested: actualDuration,
                maximum: model.maxDuration
            )
        }

        let actualAspectRatio = options.aspectRatio ?? .landscape16x9
        if !model.supportedAspectRatios.contains(actualAspectRatio) {
            throw VideoGenerationError.unsupportedAspectRatio(actualAspectRatio, model: model.displayName)
        }

        let actualResolution = options.resolution ?? model.defaultResolution
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

    /// Polls a job and returns it with the state the server reports.
    ///
    /// Sora reports progress as a percentage, which is rescaled to a fraction here. A status this
    /// client does not recognize is treated as still processing rather than as a failure, so an
    /// unfamiliar state does not end the poll early. Once the job completes the returned job
    /// carries the download URL, which always points at api.openai.com even when the client was
    /// built against a custom endpoint.
    public func checkVideoStatus(_ job: VideoGenerationJob) async throws -> VideoGenerationJob {
        let statusResponse = try await mediaClient.executeWithResponse(
            OpenAIMediaAPI.GetVideoStatus(videoId: job.id)
        ).output

        let status = mapStatus(statusResponse.status)
        var videoURL: URL?
        var errorMessage: String?

        if status == .completed {
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

    /// Downloads the rendered video.
    ///
    /// The job has to already be complete; this does not poll. The status is read from the job
    /// passed in, so a job that has not been refreshed since it was created is refused even if
    /// the server has finished rendering.
    ///
    /// - Throws: `VideoGenerationError.jobNotCompleted(status:)` when the job is in any other
    ///   state.
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
        // Sizes Sora 2 accepts:
        // sora-2: 720x1280, 1280x720
        // sora-2-pro: 720x1280, 1280x720, 1024x1792, 1792x1024
        // The 1080p tier maps to the two larger pro sizes, which only sora-2-pro renders.
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
            // Unreachable while Sora offers 16:9 and 9:16 only: the caller has already
            // rejected every other ratio.
            return "1280x720"
        }
    }

    private enum SoraStatus: String {
        case queued, processing, completed, failed, cancelled
        case inProgress = "in_progress"
        case succeeded
        case canceled

        var generationStatus: VideoGenerationStatus {
            switch self {
            case .queued: return .queued
            case .inProgress, .processing: return .processing
            case .completed, .succeeded: return .completed
            case .failed: return .failed
            case .cancelled, .canceled: return .cancelled
            }
        }
    }

    private func mapStatus(_ status: String) -> VideoGenerationStatus {
        SoraStatus(rawValue: status.lowercased())?.generationStatus ?? .processing
    }

}
