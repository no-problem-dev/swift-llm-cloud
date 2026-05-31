import Foundation
import Testing
import APIClient
import LLMClient
@testable import LLMCloudClient
@testable import LLMCloudOpenAI

@Suite("OpenAI video unified path")
struct OpenAIVideoPathTests {
    @Test("create → status → download を contract 経路で実行")
    func videoLifecycle() async throws {
        let created = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
            body: Data(#"{"id":"vid_1","status":"queued","created_at":1000}"#.utf8))
        let completed = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
            body: Data(#"{"id":"vid_1","status":"completed","created_at":1000,"progress":100}"#.utf8))
        let binary = HTTPResponse(status: 200, headers: ["Content-Type": "video/mp4"],
            body: Data([0x00, 0x00, 0x00, 0x18]))
        let mock = MockTransport([.response(created), .response(completed), .response(binary)])
        let client = OpenAIClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let job = try await client.startVideoGeneration(
            input: LLMInput("a cat"), model: .sora2, duration: nil, aspectRatio: nil, resolution: nil
        )
        #expect(job.id == "vid_1")
        #expect(job.status == .queued)

        let updated = try await client.checkVideoStatus(job)
        #expect(updated.status == .completed)

        let video = try await client.getGeneratedVideo(updated)
        #expect(video.data == Data([0x00, 0x00, 0x00, 0x18]))
        #expect(video.format == .mp4)

        #expect(mock.recordedRequests.count == 3)
        #expect(mock.recordedRequests[0].url.absoluteString == "https://api.openai.com/v1/videos")
        #expect(mock.recordedRequests[0].method == "POST")
        #expect(mock.recordedRequests[1].url.absoluteString == "https://api.openai.com/v1/videos/vid_1")
        #expect(mock.recordedRequests[2].url.absoluteString == "https://api.openai.com/v1/videos/vid_1/content")
    }
}
