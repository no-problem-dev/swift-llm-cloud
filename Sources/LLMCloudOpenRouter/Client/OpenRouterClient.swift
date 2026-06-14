import LLMCloudClient
import LLMCloudOpenAICompatible
import LLMClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenRouterModel

/// OpenRouter モデル（任意のモデルIDを文字列で指定）
public struct OpenRouterModel: Sendable, Equatable, OpenAICompatibleModelProtocol {
    /// モデルID文字列
    public let id: String

    /// 初期化
    ///
    /// - Parameter id: OpenRouter のモデル ID（例: "anthropic/claude-sonnet-4.6", "openai/gpt-5.5"）
    public init(_ id: String) {
        self.id = id
    }

    public func toLLMModel() -> LLMModel { .openRouter(id) }
}

// MARK: - Preset

extension OpenRouterModel {
    /// OpenRouter で検証済みのキュレーション済みモデルプリセット（2026年6月時点）。
    ///
    /// ベンダー → 能力の順に列挙。各ケースはツールコール対応の代表的なモデルを指す。
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

/// OpenRouter API クライアント
///
/// OpenRouter 経由で任意のモデルにアクセスするクライアントです。
/// 構造化出力、チャット、ツールコール、エージェント機能を提供します。
///
/// ## 使用例
///
/// ```swift
/// let client = OpenRouterClient(
///     apiKey: "sk-or-...",
///     appName: "MyApp",
///     siteUrl: "https://myapp.example.com"
/// )
///
/// let result: UserInfo = try await client.generate(
///     input: "山田太郎さんは35歳です。",
///     model: OpenRouterModel("anthropic/claude-sonnet-4.6")
/// )
/// ```
public struct OpenRouterClient: OpenAICompatibleClientProtocol {
    public typealias Model = OpenRouterModel

    package let engine: OpenAICompatibleEngine

    /// デフォルトエンドポイント
    public static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// API キーを指定して初期化
    ///
    /// - Parameters:
    ///   - apiKey: OpenRouter API キー
    ///   - appName: アプリ名（X-Title ヘッダー、オプション）
    ///   - siteUrl: サイト URL（HTTP-Referer ヘッダー、オプション）
    ///   - endpoint: カスタムエンドポイント（オプション）
    ///   - session: カスタム URLSession（オプション）
    ///   - retryConfiguration: リトライ設定
    ///   - retryEventHandler: リトライイベントハンドラー
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
            // OpenRouter は OpenAI 形式の max_tokens を正規パラメータとして扱う。
            maxTokensParameter: .maxTokens,
            retryConfiguration: retryConfiguration,
            retryEventHandler: retryEventHandler
        )
    }
}
