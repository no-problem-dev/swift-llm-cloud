import Foundation
import Testing
import APIClient
import LLMClient
@testable import LLMCloudClient
@testable import LLMCloudOpenAI

@Suite("OpenAI image unified path")
struct OpenAIImagePathTests {
    @Test("images/generations へ JSON POST し、b64_json を GeneratedImage にデコード")
    func generatesImage() async throws {
        // Stand-in for image bytes: the base64 of "hello", so the decoded Data is checkable.
        let b64 = Data("hello".utf8).base64EncodedString()
        let json = Data(#"{"created":1,"data":[{"b64_json":"\#(b64)","revised_prompt":"a cat"}]}"#.utf8)
        let mock = MockTransport { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
        }
        let client = OpenAIClient(transport: mock, apiKey: "k", retryConfiguration: .disabled)

        let image = try await client.generateImage(
            input: LLMInput("a cat"),
            model: .dalle3, size: .square1024, quality: nil, format: .png, n: 1
        )
        #expect(image.data == Data("hello".utf8))
        #expect(image.revisedPrompt == "a cat")

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(req.headers["authorization"] == "Bearer k")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("response_format"))
        #expect(sent.contains("b64_json"))
    }
}
