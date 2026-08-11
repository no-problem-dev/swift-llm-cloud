import LLMCloudClient
import LLMClient
// GeminiClient+VideoGeneration.swift
// swift-llm-structured-outputs
//
// Video generation through Veo.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GeminiClient + VideoGenerationCapable

extension GeminiClient: VideoGenerationCapable {
    public typealias VideoModel = GeminiVideoModel

    /// Starts a Veo video generation job and returns it in the queued state.
    ///
    /// Veo is a long-running operation: this call returns as soon as the job is accepted, with
    /// the operation name as the job id, and the video only becomes available after polling with
    /// ``checkVideoStatus(_:)``. The request is validated against the model's capabilities before
    /// it is sent, and unset parameters default to four seconds, 16:9, and 720p.
    ///
    /// - Throws: `VideoGenerationError` when the duration, aspect ratio, or resolution is one the
    ///   model does not offer, including the combination of 1080p with any duration other than
    ///   eight seconds.
    public func startVideoGeneration(
        input: LLMInput,
        model: GeminiVideoModel,
        duration: Int?,
        aspectRatio: VideoAspectRatio?,
        resolution: VideoResolution?
    ) async throws -> VideoGenerationJob {
        let prompt = input.prompt.render()
        // Reject unsupported combinations locally rather than paying for a failed job.
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

        let actualResolution = resolution ?? .hd720p
        if !model.supportedResolutions.contains(actualResolution) {
            throw VideoGenerationError.unsupportedResolution(actualResolution, model: model.displayName)
        }

        // Veo only produces 1080p at a length of exactly 8 seconds.
        if actualResolution == .fhd1080p && actualDuration != 8 {
            throw VideoGenerationError.unsupportedResolution(actualResolution, model: "\(model.displayName) (1080p requires 8 seconds)")
        }

        let body = VeoRequestBody(
            instances: [.init(prompt: prompt)],
            parameters: .init(
                aspectRatio: veoAspectRatioString(for: actualAspectRatio),
                negativePrompt: nil,
                resolution: veoResolutionString(for: actualResolution),
                durationSeconds: actualDuration
            )
        )
        let response = try await veoClient.executeWithResponse(
            GeminiMediaAPI.VeoGenerate(modelId: model.id, request: body)
        ).output

        // Keep the resolved parameters on the job; polling responses do not repeat them.
        let configuration = VideoGenerationConfiguration(
            duration: actualDuration,
            resolution: actualResolution,
            frameRate: nil,
            aspectRatio: actualAspectRatio,
            format: .mp4
        )

        return VideoGenerationJob(
            id: response.name,
            status: .queued,
            prompt: prompt,
            configuration: configuration,
            createdAt: Date()
        )
    }

    /// Polls a job once and returns it with its status brought up to date.
    ///
    /// A finished operation is completed only if it actually carries a video; an operation that
    /// reports done with neither an error nor a video is treated as failed. The progress value is
    /// a placeholder rather than a measurement, since Veo reports no percentage: it is 1.0 when
    /// complete and 0.5 while running.
    public func checkVideoStatus(_ job: VideoGenerationJob) async throws -> VideoGenerationJob {
        let operationResponse = try await veoClient.executeWithResponse(
            GeminiMediaAPI.VeoOperationStatus(operationName: job.id)
        ).output

        let status: VideoGenerationStatus
        var videoURL: URL?
        var errorMessage: String?

        if operationResponse.done == true {
            if let error = operationResponse.error {
                status = .failed
                errorMessage = error.message
            } else if let uri = operationResponse.getVideoURL() {
                status = .completed
                videoURL = URL(string: uri)
            } else if let base64 = operationResponse.getVideoBase64() {
                // Inline bytes are wrapped in a data URL so the job carries a single URL field.
                status = .completed
                videoURL = URL(string: "data:video/mp4;base64,\(base64)")
            } else {
                status = .failed
                errorMessage = "No video generated."
            }
        } else {
            status = .processing
        }

        return job.updated(
            status: status,
            videoURL: videoURL,
            errorMessage: errorMessage,
            progress: status == .completed ? 1.0 : (status == .processing ? 0.5 : nil)
        )
    }

    /// Downloads the finished video's bytes.
    ///
    /// Veo hands back a reference rather than data, in one of several forms, so the fetch depends
    /// on what the operation returned: a direct download URL, a File API path that needs a
    /// metadata lookup first, or an inline data URL. The API key is attached to every request,
    /// because these URLs are not public.
    ///
    /// - Throws: `VideoGenerationError.jobNotCompleted` when called before polling reported
    ///   completion, and `VideoGenerationError.generationFailed` when the reference cannot be
    ///   resolved or the download fails. A `gs://` reference is not supported.
    public func getGeneratedVideo(_ job: VideoGenerationJob) async throws -> GeneratedVideo {
        guard job.status == .completed else {
            throw VideoGenerationError.jobNotCompleted(status: job.status)
        }

        guard let videoURL = job.videoURL else {
            throw VideoGenerationError.generationFailed("No video URL available")
        }

        let videoData: Data
        let urlString = videoURL.absoluteString

        // Branch on the shape of the reference.
        if urlString.contains(":download") || urlString.contains("alt=media") {
            // Already a download URL; fetch it directly.
            var downloadRequest = URLRequest(url: videoURL)
            downloadRequest.httpMethod = "GET"
            downloadRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await session.data(for: downloadRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw VideoGenerationError.generationFailed("Failed to download video (status: \(statusCode))")
            }
            videoData = data
        } else if urlString.hasPrefix("gs://") || urlString.contains("files/") {
            // A File API reference: resolve it to a download URL first.
            videoData = try await downloadViaFilesAPI(uri: urlString)
        } else if urlString.hasPrefix("data:") {
            // The bytes are already here, base64 encoded in the URL.
            if let base64Start = urlString.range(of: "base64,"),
               let data = Data(base64Encoded: String(urlString[base64Start.upperBound...])) {
                videoData = data
            } else {
                throw VideoGenerationError.generationFailed("Invalid base64 data URL")
            }
        } else {
            // A plain HTTP(S) URL.
            let (data, _) = try await session.data(from: videoURL)
            videoData = data
        }

        return GeneratedVideo(
            data: videoData,
            format: .mp4,
            remoteURL: videoURL,
            duration: job.configuration?.duration.map { TimeInterval($0) },
            resolution: job.configuration?.resolution,
            jobId: job.id,
            prompt: job.prompt
        )
    }

    /// Resolves a File API reference to a download URL and fetches the bytes.
    ///
    /// Two requests: `files.get` for the metadata, which is where the usable `downloadUri` lives,
    /// then the download itself. Error messages quote the raw response, because a failure here is
    /// usually a reference in a form this does not recognize.
    private func downloadViaFilesAPI(uri: String) async throws -> Data {
        // Pull the file name out of the reference, which arrives as "files/abc123",
        // "gs://bucket/path/file.mp4", or a full API URL.
        let fileName: String

        if uri.hasPrefix("https://generativelanguage.googleapis.com/") {
            // Full API URL: keep everything from "files/" onward.
            if let range = uri.range(of: "files/") {
                fileName = String(uri[range.lowerBound...])
            } else {
                throw VideoGenerationError.generationFailed("Cannot extract file name from URL: \(uri)")
            }
        } else if uri.hasPrefix("gs://") {
            // Cloud Storage references need GCS credentials, which this client does not hold.
            throw VideoGenerationError.generationFailed("GCS URI direct download not supported: \(uri)")
        } else if uri.hasPrefix("files/") {
            // Already a bare resource name.
            fileName = uri
        } else if let range = uri.range(of: "files/") {
            // Some other path that still embeds a resource name.
            fileName = String(uri[range.lowerBound...])
        } else {
            throw VideoGenerationError.generationFailed("Unknown URI format: \(uri)")
        }

        // 1. files.get for the metadata, which carries the downloadUri.
        let fileInfoURLString = "https://generativelanguage.googleapis.com/v1beta/\(fileName)"
        guard let fileInfoURL = URL(string: fileInfoURLString) else {
            throw VideoGenerationError.generationFailed("Invalid file info URL: \(fileInfoURLString)")
        }
        var fileInfoRequest = URLRequest(url: fileInfoURL)
        fileInfoRequest.httpMethod = "GET"
        fileInfoRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (fileInfoData, fileInfoResponse) = try await session.data(for: fileInfoRequest)

        guard let httpResponse = fileInfoResponse as? HTTPURLResponse else {
            throw VideoGenerationError.generationFailed("Invalid response from files.get")
        }

        let rawFileInfoJSON = String(data: fileInfoData, encoding: .utf8) ?? "Unable to decode (binary data)"

        guard httpResponse.statusCode == 200 else {
            throw VideoGenerationError.generationFailed("Failed to get file info (status: \(httpResponse.statusCode)). Response: \(rawFileInfoJSON.prefix(500))"
            )
        }

        // Pick the downloadUri out of the metadata.
        struct FileInfo: Decodable {
            let name: String?
            let displayName: String?
            let mimeType: String?
            let sizeBytes: String?
            let uri: String?
            let downloadUri: String?
        }

        let fileInfo: FileInfo
        do {
            fileInfo = try JSONDecoder().decode(FileInfo.self, from: fileInfoData)
        } catch {
            throw VideoGenerationError.generationFailed("Failed to decode file info: \(error.localizedDescription). Raw JSON: \(rawFileInfoJSON.prefix(1000))")
        }

        guard let downloadUri = fileInfo.downloadUri else {
            throw VideoGenerationError.generationFailed("No download URI in file info. Raw JSON: \(rawFileInfoJSON.prefix(1000))")
        }

        // 2. Fetch the video from that URI.
        guard let downloadURL = URL(string: downloadUri) else {
            throw VideoGenerationError.generationFailed("Invalid download URI: \(downloadUri)")
        }

        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.httpMethod = "GET"
        // The downloadUri sometimes carries its own credentials; send the key header regardless.
        downloadRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (videoData, downloadResponse) = try await session.data(for: downloadRequest)

        guard let downloadHttpResponse = downloadResponse as? HTTPURLResponse,
              downloadHttpResponse.statusCode == 200 else {
            let statusCode = (downloadResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw VideoGenerationError.generationFailed("Failed to download video (status: \(statusCode))")
        }

        return videoData
    }

    // MARK: - Private Helpers

    private func veoAspectRatioString(for aspectRatio: VideoAspectRatio) -> String {
        switch aspectRatio {
        case .landscape16x9: return "16:9"
        case .portrait9x16: return "9:16"
        case .square1x1: return "1:1"
        case .standard4x3: return "4:3"
        case .cinematic21x9: return "21:9"
        }
    }

    private func veoResolutionString(for resolution: VideoResolution) -> String {
        switch resolution {
        case .sd480p: return "480p"
        case .hd720p: return "720p"
        case .fhd1080p: return "1080p"
        case .uhd4k: return "4k"
        }
    }

}
