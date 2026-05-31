import Foundation
import Testing
import APIClient
import LLMClient
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini video unified path")
struct GeminiVideoPathTests {
    @Test("predictLongRunning で作成 → operations でステータス取得")
    func createAndStatus() async throws {
        let createJSON = Data(#"{"name":"models/veo-3.0/operations/op_1","done":false}"#.utf8)
        let statusJSON = Data(#"{"name":"models/veo-3.0/operations/op_1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://example.com/v.mp4"}}]}}}"#.utf8)
        let mock = MockTransport([
            .response(HTTPResponse(status: 200, headers: [:], body: createJSON)),
            .response(HTTPResponse(status: 200, headers: [:], body: statusJSON)),
        ])
        let client = GeminiClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let job = try await client.startVideoGeneration(
            input: LLMInput("a cat"), model: .veo30, duration: nil, aspectRatio: nil, resolution: nil
        )
        #expect(job.id == "models/veo-3.0/operations/op_1")
        #expect(job.status == .queued)

        let updated = try await client.checkVideoStatus(job)
        #expect(updated.status == .completed)
        #expect(updated.videoURL?.absoluteString == "https://example.com/v.mp4")

        let createReq = mock.recordedRequests[0]
        #expect(createReq.url.absoluteString.contains(":predictLongRunning"))
        #expect(createReq.url.absoluteString.contains("/v1beta/models/"))
        #expect(createReq.headers["x-goog-api-key"] == "k")
        let sent = String(decoding: try #require(createReq.body), as: UTF8.self)
        #expect(sent.contains("durationSeconds"))
        #expect(sent.contains("instances"))

        let statusReq = mock.recordedRequests[1]
        #expect(statusReq.url.absoluteString.contains("/v1beta/models/veo-3.0/operations/op_1"))
        #expect(statusReq.method == "GET")
    }
}
