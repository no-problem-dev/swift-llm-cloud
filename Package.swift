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
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "3.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "1.1.0"),
        .package(url: "https://github.com/no-problem-dev/swift-api-contract.git", from: "2.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "2.1.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // Shared provider infrastructure
        .target(name: "LLMCloudClient", dependencies: [
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "APIClient", package: "swift-api-client"),
        ]),
        // OpenAI-compatible shared infrastructure
        .target(name: "LLMCloudOpenAICompatible", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
        ]),
        // Anthropic provider
        .target(name: "LLMCloudAnthropic", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
        ], exclude: [
            "Extensions/AnthropicClient+Dynamic.swift",
        ]),
        // OpenAI provider (depends on OpenAICompatible)
        .target(name: "LLMCloudOpenAI", dependencies: [
            "LLMCloudOpenAICompatible",
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
        ]),
        // Gemini provider
        .target(name: "LLMCloudGemini", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "APIContract", package: "swift-api-contract"),
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "StructuredDataCore", package: "swift-structured-data"),
        ], exclude: [
            "Extensions/GeminiClient+Dynamic.swift",
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
        // Tests
        .testTarget(name: "LLMCloudClientTests", dependencies: ["LLMCloudClient"]),
        .testTarget(name: "LLMCloudAnthropicTests", dependencies: [
            "LLMCloudAnthropic", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .testTarget(name: "LLMCloudOpenAITests", dependencies: [
            "LLMCloudOpenAI", "LLMCloudOpenAICompatible", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .testTarget(name: "LLMCloudGeminiTests", dependencies: [
            "LLMCloudGemini", "LLMCloudClient",
            .product(name: "APIClient", package: "swift-api-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
    ]
)
