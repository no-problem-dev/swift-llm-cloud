import Foundation

/// クラウド LLM プロバイダー / モデルファミリーのブランド identity。
///
/// ロゴアセット（`ProviderLogos.xcassets`）とプロバイダーの表示名を 1 箇所に束ねる。
/// アプリ側はプロバイダー / モデルをこの brand に解決し、`CloudProviderLogo` で描画する。
/// クラウドへの依存（`swift-llm-cloud`）を 1 ターゲットに閉じ込めるための公開 identity でもある。
public enum CloudProviderBrand: String, CaseIterable, Identifiable, Sendable, Hashable, Codable {
    // クラウドプロバイダー（API 提供元）
    case anthropic
    case openai
    case google
    case xai
    case deepseek
    case groq
    case mistral
    case openRouter
    // モデルファミリー / 周辺（OpenRouter 経由などで現れるベンダー）
    case meta
    case qwen
    case microsoft
    case ibm
    case huggingface
    // 検索プロバイダー（researcher / visualizer の web 検索）
    case brave
    // オンデバイス（MLX 等）
    case local

    public var id: String { rawValue }

    /// 人間向け表示名。
    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .google: "Google Gemini"
        case .xai: "xAI"
        case .deepseek: "DeepSeek"
        case .groq: "Groq"
        case .mistral: "Mistral"
        case .openRouter: "OpenRouter"
        case .meta: "Meta"
        case .qwen: "Qwen"
        case .microsoft: "Microsoft"
        case .ibm: "IBM"
        case .huggingface: "Hugging Face"
        case .brave: "Brave"
        case .local: "オンデバイス"
        }
    }

    /// `ProviderLogos.xcassets` 内のロゴ画像名。
    public var logoAssetName: String {
        switch self {
        case .anthropic: "claude-logo"
        case .openai: "openai-logo"
        case .google: "google-logo"
        case .xai: "xai-logo"
        case .deepseek: "deepseek-logo"
        case .groq: "groq-logo"
        case .mistral: "mistral-logo"
        case .openRouter: "openrouter-logo"
        case .meta: "meta-logo"
        case .qwen: "qwen-logo"
        case .microsoft: "microsoft-logo"
        case .ibm: "ibm-logo"
        case .huggingface: "huggingface-logo"
        case .brave: "brave-logo"
        case .local: "local-logo"
        }
    }

    /// アセットが無く SF Symbols へフォールバックするか（現状は全 brand にアセットあり）。
    public var usesSystemImage: Bool { false }

    /// アセットが無い場合に使う SF Symbols 名。
    public var systemImageName: String {
        switch self {
        case .local: "desktopcomputer"
        default: "sparkles"
        }
    }

    /// モデルファミリー名（`ModelProfile.modelFamily` 等）からブランドを推定する。
    /// プロバイダー非依存の表示側が、モデル ID/ファミリーだけからロゴを引くために使う。
    public static func from(modelFamily family: String) -> CloudProviderBrand? {
        switch family.lowercased() {
        case "claude", "anthropic": .anthropic
        case "gpt", "o-series", "openai": .openai
        case "gemini", "gemma", "google": .google
        case "grok", "xai": .xai
        case "deepseek": .deepseek
        case "mistral", "magistral", "codestral", "ministral", "devstral": .mistral
        case "llama", "meta": .meta
        case "qwen", "qwq": .qwen
        case "groq": .groq
        case "phi", "microsoft": .microsoft
        case "granite", "ibm": .ibm
        default: nil
        }
    }
}
