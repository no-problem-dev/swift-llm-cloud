import Foundation
import Testing
import APIClient
import LLMClient
@testable import LLMCloudClient
@testable import LLMCloudOpenAI

@Suite("OpenAI speech unified path")
struct OpenAISpeechPathTests {
    @Test("audio/speech にバイナリ POST し、生 Data を GeneratedAudio に包む")
    func generatesSpeech() async throws {
        let audio = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x01, 0x02])
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "audio/mpeg"], body: audio)
        }
        let client = OpenAIClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let result = try await client.generateSpeech(
            input: LLMInput("hello world"),
            model: .tts1, voice: .alloy, speed: 1.0, format: .mp3
        )
        #expect(result.data == audio)
        #expect(result.format == .mp3)
        #expect(result.transcript?.contains("hello world") == true)

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(req.headers["authorization"] == "Bearer k")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("response_format"))
        #expect(sent.contains("\"voice\""))
    }
}
