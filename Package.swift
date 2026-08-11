// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-cloud",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LLMCloudClient", targets: ["LLMCloudClient"]),
        .library(name: "LLMCloudOpenAICompatible", targets: ["LLMCloudOpenAICompatible"]),
        .library(name: "LLMCloudAnthropic", targets: ["LLMCloudAnthropic"]),
        .library(name: "LLMCloudOpenAI", targets: ["LLMCloudOpenAI"]),
        .library(name: "LLMCloudGemini", targets: ["LLMCloudGemini"]),
        .library(name: "LLMCloudDeepSeek", targets: ["LLMCloudDeepSeek"]),
        .library(name: "LLMCloudXAI", targets: ["LLMCloudXAI"]),
        .library(name: "LLMCloudGroq", targets: ["LLMCloudGroq"]),
        .library(name: "LLMCloudMistral", targets: ["LLMCloudMistral"]),
        .library(name: "LLMCloudOpenRouter", targets: ["LLMCloudOpenRouter"]),
        .library(name: "LLMCloud", targets: ["LLMCloud"]),
        // プロバイダー / モデルファミリーのブランドロゴ + 表示 identity（SwiftUI）。
        // クラウド依存の表示資産を 1 ターゲットに閉じ込めるための公開モジュール。
        .library(name: "LLMCloudBranding", targets: ["LLMCloudBranding"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "5.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "3.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-api-contract.git", from: "2.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "5.0.0"),
        // api-client 3.0.3 stopped re-exporting HTTPTransport, so the transport types this
        // package names in its own initializers have to be depended on directly.
        .package(url: "https://github.com/no-problem-dev/swift-http-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // Shared provider infrastructure
        .target(name: "LLMCloudClient", dependencies: [
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "JSONParsing", package: "swift-structured-data"),
        ]),
        // OpenAI-compatible shared infrastructure
        .target(name: "LLMCloudOpenAICompatible", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMAgentStep", package: "swift-llm-client"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "JSONParsing", package: "swift-structured-data"),
        ]),
        // Anthropic provider
        .target(name: "LLMCloudAnthropic", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMAgentStep", package: "swift-llm-client"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "JSONParsing", package: "swift-structured-data"),
        ]),
        // OpenAI provider (depends on OpenAICompatible)
        .target(name: "LLMCloudOpenAI", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMAgentStep", package: "swift-llm-client"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "JSONParsing", package: "swift-structured-data"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "APIContract", package: "swift-api-contract"),
        ]),
        // Gemini provider
        .target(name: "LLMCloudGemini", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMAgentStep", package: "swift-llm-client"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "JSONParsing", package: "swift-structured-data"),
        ]),
        // DeepSeek provider
        .target(name: "LLMCloudDeepSeek", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
        ]),
        // xAI provider
        .target(name: "LLMCloudXAI", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
        ]),
        // Groq provider
        .target(name: "LLMCloudGroq", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
        ]),
        // Mistral provider
        .target(name: "LLMCloudMistral", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
        ]),
        // OpenRouter provider
        .target(name: "LLMCloudOpenRouter", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
        ]),
        // Umbrella re-export
        .target(name: "LLMCloud", dependencies: [
            "LLMCloudClient",
            "LLMCloudAnthropic",
            "LLMCloudOpenAI",
            "LLMCloudGemini",
        ]),
        // プロバイダー / モデルファミリーのブランドロゴ + 表示 identity。
        // ロゴアセット（ProviderLogos.xcassets）を同梱し SwiftUI ビューで描画する。
        // 他ターゲットには依存しない（純粋な表示資産）。
        .target(
            name: "LLMCloudBranding",
            resources: [.process("Resources/ProviderLogos.xcassets")]
        ),
        // Tests
        .testTarget(name: "LLMCloudClientTests", dependencies: ["LLMCloudClient"]),
        .testTarget(name: "LLMCloudAnthropicTests", dependencies: [
            "LLMCloudAnthropic", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .testTarget(name: "LLMCloudOpenAITests", dependencies: [
            "LLMCloudOpenAI", "LLMCloudOpenAICompatible", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .testTarget(name: "LLMCloudGeminiTests", dependencies: [
            "LLMCloudGemini", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "HTTPTransport", package: "swift-http-transport"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
    ]
)
