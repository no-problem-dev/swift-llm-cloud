// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-cloud",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LLMCloudClient", targets: ["LLMCloudClient"]),
        .library(name: "LLMCloudAnthropic", targets: ["LLMCloudAnthropic"]),
        .library(name: "LLMCloudOpenAI", targets: ["LLMCloudOpenAI"]),
        .library(name: "LLMCloudGemini", targets: ["LLMCloudGemini"]),
        .library(name: "LLMCloud", targets: ["LLMCloud"]),
    ],
    dependencies: [
        .package(path: "../swift-llm-client"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // Shared provider infrastructure
        .target(name: "LLMCloudClient", dependencies: [
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        // Anthropic provider
        .target(name: "LLMCloudAnthropic", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "LLMDynamicStructured", package: "swift-llm-client"),
        ]),
        // OpenAI provider
        .target(name: "LLMCloudOpenAI", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "LLMDynamicStructured", package: "swift-llm-client"),
        ]),
        // Gemini provider
        .target(name: "LLMCloudGemini", dependencies: [
            "LLMCloudClient",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "LLMChat", package: "swift-llm-client"),
            .product(name: "LLMDynamicStructured", package: "swift-llm-client"),
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
        .testTarget(name: "LLMCloudAnthropicTests", dependencies: ["LLMCloudAnthropic", "LLMCloudClient"]),
        .testTarget(name: "LLMCloudOpenAITests", dependencies: ["LLMCloudOpenAI", "LLMCloudClient"]),
        .testTarget(name: "LLMCloudGeminiTests", dependencies: ["LLMCloudGemini", "LLMCloudClient"]),
    ]
)
