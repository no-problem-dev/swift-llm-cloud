import Foundation
import Testing
import APIClient
import LLMClient
import HTTPTransport
@testable import LLMCloudClient
@testable import LLMCloudGemini

@Suite("Gemini image unified path")
struct GeminiImagePathTests {
    private func client(_ transport: any HTTPTransport & HTTPStreamingTransport) -> GeminiClient {
        GeminiClient(transport: transport, apiKey: "k", retryConfiguration: .disabled)
    }

    @Test("Imagen :predict へ POST し、bytesBase64Encoded をデコード、x-goog-api-key 認証")
    func imagenPredict() async throws {
        let b64 = Data("img".utf8).base64EncodedString()
        let json = Data(#"{"predictions":[{"bytesBase64Encoded":"\#(b64)","mimeType":"image/png"}]}"#.utf8)
        let mock = MockTransport { _ in HTTPResponse(status: 200, headers: [:], body: json) }

        let image = try await client(mock).generateImage(
            input: LLMInput("a cat"), model: .imagen4, size: .square1024, quality: nil, format: .png, n: 1
        )
        #expect(image.data == Data("img".utf8))

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString.contains(":predict"))
        #expect(req.headers["x-goog-api-key"] == "k")
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("sampleCount"))
        #expect(sent.contains("aspectRatio"))
    }

    @Test("Gemini Image :generateContent の inlineData をデコード")
    func geminiImageGenerate() async throws {
        let b64 = Data("png".utf8).base64EncodedString()
        let json = Data(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\#(b64)"}}]}}]}"#.utf8)
        let mock = MockTransport { _ in HTTPResponse(status: 200, headers: [:], body: json) }

        let image = try await client(mock).generateImage(
            input: LLMInput("a dog"), model: .gemini20FlashImage, size: .square1024, quality: nil, format: .png, n: 1
        )
        #expect(image.data == Data("png".utf8))

        let req = try #require(mock.recordedRequests.first)
        #expect(req.url.absoluteString.contains(":generateContent"))
        let sent = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(sent.contains("responseModalities"))
    }
}
