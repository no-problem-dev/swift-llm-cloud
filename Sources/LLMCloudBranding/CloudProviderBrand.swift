import Foundation

/// A vendor an app can show a name and a logo for.
///
/// Covers more than the providers this package can talk to: a model reached through OpenRouter
/// is served by one vendor but built by another, and an app usually wants to show the one that
/// built it. So model families such as Llama and Qwen get their own cases alongside the API
/// vendors, plus the Brave search backend and on-device inference.
///
/// The names and assets live here so an app can display a provider without importing the client
/// modules. Resolve a provider or model to a case, then draw it with ``CloudProviderLogo``.
public enum CloudProviderBrand: String, CaseIterable, Identifiable, Sendable, Hashable, Codable {
    // Cloud providers (API vendors)
    case anthropic
    case openai
    case google
    case xai
    case deepseek
    case groq
    case mistral
    case openRouter
    // Model families and adjacent vendors, which surface through OpenRouter and the like
    case meta
    case qwen
    case microsoft
    case ibm
    case huggingface
    // Search backend used by the researcher and visualizer web search
    case brave
    // On-device inference, such as MLX
    case local

    public var id: String { rawValue }

    /// The vendor's name as it should appear in the interface.
    ///
    /// Spelled the way each vendor spells it, so casing is deliberate. Not localized, except for
    /// on-device inference, which has no vendor to name and reads as Japanese UI text.
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

    /// Name of the logo image in the asset catalog this package ships.
    ///
    /// Load it from `Bundle.module`, not the main bundle — or let ``CloudProviderLogo`` do it.
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

    /// Whether the brand has to fall back to an SF Symbol instead of a shipped logo.
    ///
    /// False for every brand: the asset catalog covers all of them. It stays as a hook so a
    /// brand added without artwork can still render.
    public var usesSystemImage: Bool { false }

    /// SF Symbol to draw when no logo asset is available.
    public var systemImageName: String {
        switch self {
        case .local: "desktopcomputer"
        default: "sparkles"
        }
    }

    /// Resolves a model family name to the brand that built it.
    ///
    /// Lets a view that only knows which model is selected draw the right logo, without knowing
    /// which provider is serving it. Matching is case-insensitive and covers both the family
    /// name and the vendor name, so `"claude"` and `"anthropic"` both land on the same brand.
    /// Several families map to one brand — Mistral's Codestral and Devstral among them.
    ///
    /// Returns nil for an unrecognized family, and several brands have no family that reaches
    /// them at all — OpenRouter, Hugging Face, Brave, and on-device among them.
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
