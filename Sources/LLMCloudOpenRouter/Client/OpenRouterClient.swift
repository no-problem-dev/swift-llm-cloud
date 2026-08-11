import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenRouterModel

/// A model addressed by the provider-qualified ID string that OpenRouter routes on.
///
/// OpenRouter's catalogue spans many upstream providers and changes faster than a release of this
/// package, so the model is carried as a free-form string rather than an enum. Curated,
/// tool-call-capable choices are available as ``OpenRouterModel/Preset`` values.
public struct OpenRouterModel: Sendable, Equatable, OpenAICompatibleModelProtocol {
    /// Provider-qualified model ID, sent verbatim as the request's model field.
    ///
    /// The form is `vendor/model`, for example `anthropic/claude-sonnet-4.6`. This string decides
    /// which upstream provider serves the request, and with it the price, the context window, and
    /// the rate limits that apply.
    public let id: String

    /// Creates a model reference from an OpenRouter model ID.
    ///
    /// The ID is neither validated nor normalized here. A misspelled or retired ID travels to the
    /// API and comes back as a 404, surfaced as a model-not-found error rather than a local one.
    ///
    /// - Parameter id: OpenRouter model ID, such as `anthropic/claude-sonnet-4.6` or `openai/gpt-5.5`.
    public init(_ id: String) {
        self.id = id
    }

    public func toLLMModel() -> LLMModel { .openRouter(id) }
}

// MARK: - Preset

extension OpenRouterModel {
    /// Curated models verified on OpenRouter, as of June 2026.
    ///
    /// Cases are grouped by upstream vendor, and every one of them supports tool calling, so any
    /// preset can drive an agent loop. This is a hand-maintained shortlist, not the catalogue:
    /// OpenRouter serves far more models, and anything absent here is still reachable by building
    /// an ``OpenRouterModel`` from its ID.
    ///
    /// The raw values are the case names, so they are stable across model-ID churn and safe to
    /// persist as a user's model preference.
    public enum Preset: String, CaseIterable, Identifiable, Codable, Sendable {
        // MARK: Anthropic
        case claudeOpus48 = "claudeOpus48"
        case claudeSonnet46 = "claudeSonnet46"
        case claudeHaiku45 = "claudeHaiku45"

        // MARK: OpenAI
        case gpt55 = "gpt55"
        case gpt52 = "gpt52"

        // MARK: Google
        case gemini31Pro = "gemini31Pro"
        case gemini3Flash = "gemini3Flash"

        // MARK: xAI
        case grok420 = "grok420"

        // MARK: DeepSeek
        case deepseekV4Pro = "deepseekV4Pro"
        case deepseekV32 = "deepseekV32"

        // MARK: Meta
        case llama4Maverick = "llama4Maverick"

        // MARK: Mistral
        case mistralLarge3 = "mistralLarge3"

        // MARK: Qwen
        case qwen37Max = "qwen37Max"

        // MARK: Moonshot
        case kimiK26 = "kimiK26"

        public var id: String { rawValue }

        public var model: OpenRouterModel {
            switch self {
            case .claudeOpus48: return OpenRouterModel("anthropic/claude-opus-4.8")
            case .claudeSonnet46: return OpenRouterModel("anthropic/claude-sonnet-4.6")
            case .claudeHaiku45: return OpenRouterModel("anthropic/claude-haiku-4.5")
            case .gpt55: return OpenRouterModel("openai/gpt-5.5")
            case .gpt52: return OpenRouterModel("openai/gpt-5.2")
            case .gemini31Pro: return OpenRouterModel("google/gemini-3.1-pro-preview")
            case .gemini3Flash: return OpenRouterModel("google/gemini-3-flash-preview")
            case .grok420: return OpenRouterModel("x-ai/grok-4.20")
            case .deepseekV4Pro: return OpenRouterModel("deepseek/deepseek-v4-pro")
            case .deepseekV32: return OpenRouterModel("deepseek/deepseek-v3.2")
            case .llama4Maverick: return OpenRouterModel("meta-llama/llama-4-maverick")
            case .mistralLarge3: return OpenRouterModel("mistralai/mistral-large-2512")
            case .qwen37Max: return OpenRouterModel("qwen/qwen3.7-max")
            case .kimiK26: return OpenRouterModel("moonshotai/kimi-k2.6")
            }
        }

        public var displayName: String {
            switch self {
            case .claudeOpus48: return "Claude Opus 4.8"
            case .claudeSonnet46: return "Claude Sonnet 4.6"
            case .claudeHaiku45: return "Claude Haiku 4.5"
            case .gpt55: return "GPT-5.5"
            case .gpt52: return "GPT-5.2"
            case .gemini31Pro: return "Gemini 3.1 Pro"
            case .gemini3Flash: return "Gemini 3 Flash"
            case .grok420: return "Grok 4.20"
            case .deepseekV4Pro: return "DeepSeek V4 Pro"
            case .deepseekV32: return "DeepSeek V3.2"
            case .llama4Maverick: return "Llama 4 Maverick"
            case .mistralLarge3: return "Mistral Large 3"
            case .qwen37Max: return "Qwen3.7 Max"
            case .kimiK26: return "Kimi K2.6"
            }
        }

        public var shortName: String {
            switch self {
            case .claudeOpus48: return "Opus 4.8"
            case .claudeSonnet46: return "Sonnet 4.6"
            case .claudeHaiku45: return "Haiku 4.5"
            case .gpt55: return "GPT-5.5"
            case .gpt52: return "GPT-5.2"
            case .gemini31Pro: return "Gemini 3.1 Pro"
            case .gemini3Flash: return "Gemini 3 Flash"
            case .grok420: return "Grok 4.20"
            case .deepseekV4Pro: return "V4 Pro"
            case .deepseekV32: return "V3.2"
            case .llama4Maverick: return "Llama 4 Maverick"
            case .mistralLarge3: return "Mistral Large 3"
            case .qwen37Max: return "Qwen3.7 Max"
            case .kimiK26: return "Kimi K2.6"
            }
        }

        /// Capability and price snapshot recorded for the preset when it was curated.
        ///
        /// These figures are literals maintained in this package, not fetched from OpenRouter, so
        /// treat them as guidance for picking a model rather than as billing truth. Pricing and
        /// limits belong to whichever upstream provider OpenRouter routes the request to, and the
        /// per-million-token rates here are the list prices seen at curation time.
        public var profile: ModelProfile {
            switch self {
            case .claudeOpus48:
                return ModelProfile(
                    summary: "最高性能。複雑な推論・エージェント構築に最適",
                    modelFamily: "Claude",
                    description: "Anthropic の現フラッグシップ。複雑な多段階推論と高度なコード生成に優れ、1M トークンの超大容量コンテキストを備える。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["複雑な推論", "コード生成", "エージェント構築", "超大容量コンテキスト"],
                    bestFor: ["エージェントワークフロー", "複雑な分析・推論", "長文コード生成"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 5, outputPerMTok: 25)
                )
            case .claudeSonnet46:
                return ModelProfile(
                    summary: "バランス型。速度と品質の最適なトレードオフ",
                    modelFamily: "Claude",
                    description: "速度と知性のバランスに優れた Claude モデル。1M トークンのコンテキストでコーディングや汎用タスクに幅広く対応。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["速度と品質のバランス", "コーディング", "超大容量コンテキスト"],
                    bestFor: ["高スループット分析", "コーディングタスク", "コスト効率重視の汎用タスク"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 3, outputPerMTok: 15)
                )
            case .claudeHaiku45:
                return ModelProfile(
                    summary: "高速・低コスト。軽量タスクに最適",
                    modelFamily: "Claude",
                    description: "最速の Claude モデル。フロンティアに近い知性を低コストで提供し、リアルタイムチャットや大量処理に向く。OpenRouter 経由でアクセス。",
                    contextWindow: 200_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["高速応答", "低コスト", "大量処理向き"],
                    bestFor: ["リアルタイムチャット", "大量バッチ処理", "コスト重視のアプリケーション"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 1, outputPerMTok: 5)
                )
            case .gpt55:
                return ModelProfile(
                    summary: "OpenAI フラッグシップ。最高水準の汎用知性",
                    modelFamily: "GPT",
                    description: "OpenAI の現フラッグシップ。幅広いタスクで最高水準の推論・コード生成性能を発揮し、1M トークンのコンテキストに対応。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["高度な推論", "コード生成", "マルチモーダル", "超大容量コンテキスト"],
                    bestFor: ["複雑な推論タスク", "エージェントワークフロー", "高品質コンテンツ生成"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 5, outputPerMTok: 30)
                )
            case .gpt52:
                return ModelProfile(
                    summary: "コスト効率の高い GPT-5 世代の汎用モデル",
                    modelFamily: "GPT",
                    description: "GPT-5.2 は高い知性をより低コストで提供する汎用モデル。1M トークンのコンテキストで日常的なタスクに幅広く対応。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["コスト効率", "汎用性能", "超大容量コンテキスト"],
                    bestFor: ["汎用チャット", "コスト効率重視のタスク", "中規模の分析"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 1.75, outputPerMTok: 14)
                )
            case .gemini31Pro:
                return ModelProfile(
                    summary: "Google の高性能マルチモーダルモデル",
                    modelFamily: "Gemini",
                    description: "Gemini 3.1 Pro は Google の高性能モデル。強力なマルチモーダル理解と長文コンテキスト処理を備える。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["マルチモーダル理解", "長文処理", "超大容量コンテキスト"],
                    bestFor: ["マルチモーダル分析", "長文ドキュメント処理", "汎用推論"],
                    toolCallSupport: .good,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 2, outputPerMTok: 12)
                )
            case .gemini3Flash:
                return ModelProfile(
                    summary: "高速・低コストの Gemini モデル",
                    modelFamily: "Gemini",
                    description: "Gemini 3 Flash は速度とコスト効率を重視した Gemini モデル。大量処理やリアルタイム用途に向く。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["高速応答", "低コスト", "超大容量コンテキスト"],
                    bestFor: ["リアルタイム処理", "大量バッチ処理", "コスト重視のタスク"],
                    toolCallSupport: .good,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 0.50, outputPerMTok: 3)
                )
            case .grok420:
                return ModelProfile(
                    summary: "超大容量コンテキストの xAI モデル",
                    modelFamily: "Grok",
                    description: "Grok 4.20 は xAI のモデルで、2M トークンの超大容量コンテキストを備える。長文処理とエージェント用途に強い。OpenRouter 経由でアクセス。",
                    contextWindow: 2_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["超大容量コンテキスト", "長文処理", "エージェント構築"],
                    bestFor: ["超長文ドキュメント処理", "エージェントワークフロー", "大規模コンテキスト分析"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 1.25, outputPerMTok: 2.50)
                )
            case .deepseekV4Pro:
                return ModelProfile(
                    summary: "高コスパなコード特化 DeepSeek モデル",
                    modelFamily: "DeepSeek",
                    description: "DeepSeek V4 Pro はコードと推論に強い高コスパモデル。1M トークンのコンテキストでコーディングタスクに最適。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["コード生成", "推論", "高コスパ", "超大容量コンテキスト"],
                    bestFor: ["コーディングタスク", "コスト効率重視の推論", "大規模コード分析"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.435, outputPerMTok: 0.87)
                )
            case .deepseekV32:
                return ModelProfile(
                    summary: "低コストなコード特化 DeepSeek モデル",
                    modelFamily: "DeepSeek",
                    description: "DeepSeek V3.2 は低コストでコードと推論に対応するモデル。コスト重視の開発タスクに向く。OpenRouter 経由でアクセス。",
                    contextWindow: 131_072,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["コード生成", "低コスト", "推論"],
                    bestFor: ["コスト重視のコーディング", "軽量な推論タスク", "バッチ処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.23, outputPerMTok: 0.34)
                )
            case .llama4Maverick:
                return ModelProfile(
                    summary: "オープンウェイトの高コスパマルチモーダルモデル",
                    modelFamily: "Llama",
                    description: "Llama 4 Maverick は Meta のオープンウェイトモデル。マルチモーダル対応かつ非常に低コストで、1M トークンのコンテキストを備える。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["低コスト", "マルチモーダル", "オープンウェイト", "超大容量コンテキスト"],
                    bestFor: ["コスト重視の汎用タスク", "マルチモーダル処理", "大量処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 0.15, outputPerMTok: 0.60)
                )
            case .mistralLarge3:
                return ModelProfile(
                    summary: "Mistral の高性能マルチモーダルモデル",
                    modelFamily: "Mistral",
                    description: "Mistral Large 3 は Mistral AI の高性能モデル。マルチモーダル対応で、汎用推論とコード生成に幅広く対応。OpenRouter 経由でアクセス。",
                    contextWindow: 262_144,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["汎用推論", "コード生成", "マルチモーダル"],
                    bestFor: ["汎用タスク", "コーディング", "マルチモーダル分析"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 0.50, outputPerMTok: 1.50)
                )
            case .qwen37Max:
                return ModelProfile(
                    summary: "Alibaba の高性能コード特化モデル",
                    modelFamily: "Qwen",
                    description: "Qwen3.7 Max は Alibaba のフラッグシップ。コードと推論に強く、1M トークンの超大容量コンテキストを備える。OpenRouter 経由でアクセス。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["コード生成", "推論", "超大容量コンテキスト"],
                    bestFor: ["コーディングタスク", "大規模コード分析", "汎用推論"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 1.25, outputPerMTok: 3.75)
                )
            case .kimiK26:
                return ModelProfile(
                    summary: "Moonshot のコード特化モデル",
                    modelFamily: "Kimi",
                    description: "Kimi K2.6 は Moonshot AI のモデル。コードと推論に強く、長文コンテキスト処理に対応。OpenRouter 経由でアクセス。",
                    contextWindow: 262_144,
                    maxOutputTokens: nil,
                    knowledgeCutoff: nil,
                    strengths: ["コード生成", "推論", "長文処理"],
                    bestFor: ["コーディングタスク", "長文ドキュメント処理", "汎用推論"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.68, outputPerMTok: 3.41)
                )
            }
        }
    }
}

// MARK: - OpenRouterClient

/// Client for OpenRouter, one OpenAI-compatible API that proxies to many upstream providers.
///
/// Structured output, chat, tool calls, and agent steps all come from the shared
/// `OpenAICompatibleEngine`; this type pins the OpenRouter endpoint, the optional attribution
/// headers, and the request quirk. Any model is addressable by ID through ``OpenRouterModel``,
/// with curated choices in ``OpenRouterModel/Preset``.
///
/// The output cap is sent as `max_tokens`, which is OpenRouter's canonical field for it.
///
/// Because every request is routed onward, much of what looks like OpenRouter's behaviour is
/// really the chosen model's: which usage fields come back (cached prompt tokens, reasoning
/// tokens), what the rate limits are, and whether `x-ratelimit-*` headers appear at all follow
/// from whichever upstream provider served the call. When those headers are absent, a retry has no
/// server-supplied reset hint to honour and falls back to plain exponential backoff.
///
/// Requests are never streamed: `streamAgentStep` falls back to the shared non-streaming
/// implementation and yields one completed event at the end rather than deltas.
///
/// ## Example
///
/// ```swift
/// let client = OpenRouterClient(
///     apiKey: "sk-or-...",
///     appName: "MyApp",
///     siteUrl: "https://myapp.example.com"
/// )
///
/// let result: UserInfo = try await client.generate(
///     input: "Taro Yamada is 35 years old.",
///     model: OpenRouterModel("anthropic/claude-sonnet-4.6")
/// )
/// ```
public struct OpenRouterClient: OpenAICompatibleClientProtocol {
    public typealias Model = OpenRouterModel

    package let engine: OpenAICompatibleEngine

    /// Full chat-completions URL used when the caller does not supply one.
    ///
    /// The API contract has an empty base path, so this URL is sent verbatim. A replacement must
    /// be a complete completions URL rather than a host, and must not end in a slash — a trailing
    /// slash is what made the sibling Groq endpoint answer `Unknown request URL`.
    public static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Creates a client that authenticates with the given OpenRouter API key.
    ///
    /// The key is sent as an `Authorization: Bearer` header. The two attribution arguments become
    /// headers only when non-nil: `appName` is sent as `X-Title` and `siteUrl` as `HTTP-Referer`,
    /// which is how OpenRouter credits traffic to an app. Omitting them changes nothing about how
    /// a request is served; it only leaves the call unattributed.
    ///
    /// Retries are on by default (up to five after the first failure): retryable failures such as
    /// 429 and 5xx back off exponentially with jitter, and a `Retry-After` or `x-ratelimit-reset-*`
    /// hint overrides the curve when the routed provider supplies one. Retries cover `generate` and
    /// `executeAgentStep`; `chat` and `planToolCalls` are sent exactly once.
    ///
    /// - Parameters:
    ///   - apiKey: OpenRouter API key.
    ///   - appName: Application name, sent as the `X-Title` attribution header.
    ///   - siteUrl: Site URL, sent as the `HTTP-Referer` attribution header.
    ///   - endpoint: Replaces ``defaultEndpoint``; must be a complete chat-completions URL.
    ///   - session: Session backing the HTTP transport.
    ///   - retryConfiguration: Retry budget and backoff bounds. Pass `.disabled` to fail on the
    ///     first error.
    ///   - retryEventHandler: Called before each retry sleeps, with the attempt number, the error,
    ///     and the delay that was chosen.
    public init(
        apiKey: String,
        appName: String? = nil,
        siteUrl: String? = nil,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        retryConfiguration: RetryConfiguration = .default,
        retryEventHandler: RetryEventHandler? = nil
    ) {
        var customHeaders: [String: String] = [:]
        if let appName = appName {
            customHeaders["X-Title"] = appName
        }
        if let siteUrl = siteUrl {
            customHeaders["HTTP-Referer"] = siteUrl
        }

        self.engine = OpenAICompatibleEngine(
            apiKey: apiKey,
            endpoint: endpoint ?? Self.defaultEndpoint,
            providerName: "OpenRouter",
            session: session,
            customHeaders: customHeaders,
            // OpenRouter's canonical field for the output cap is OpenAI's max_tokens.
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
