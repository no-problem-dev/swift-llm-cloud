import Foundation

// MARK: - Claude Models

/// Anthropic Claude モデル
///
/// エイリアス（推奨）または固定バージョンでモデルを指定できます。
///
/// ## エイリアス（推奨）
/// ```swift
/// let client = AnthropicClient(apiKey: "...")
/// let result: UserInfo = try await client.generate(
///     input: "...",
///     model: .sonnet  // 最新の Sonnet を使用
/// )
/// ```
///
/// ## 固定バージョン
/// ```swift
/// let result: UserInfo = try await client.generate(
///     input: "...",
///     model: .opus4_6("20260210")  // 特定バージョンを指定
/// )
/// ```
///
/// ## カスタムモデルID
/// ```swift
/// let result: UserInfo = try await client.generate(
///     input: "...",
///     model: .custom("claude-opus-4-6-20260210")
/// )
/// ```
public enum ClaudeModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)

    /// Claude Opus 最新版（最高性能）
    case opus

    /// Claude Sonnet 最新版（バランス型）
    case sonnet

    /// Claude Haiku 最新版（高速・低コスト）
    case haiku

    // MARK: - Fixed Versions

    /// Claude Opus 4.6 固定バージョン
    case opus4_6(version: String)

    /// Claude Sonnet 4.6 固定バージョン
    case sonnet4_6(version: String)

    /// Claude Opus 4.5 固定バージョン
    case opus4_5(version: String)

    /// Claude Sonnet 4.5 固定バージョン
    case sonnet4_5(version: String)

    /// Claude Haiku 4.5 固定バージョン
    case haiku4_5(version: String)

    /// Claude Opus 4.1 固定バージョン
    case opus4_1(version: String)

    /// Claude Opus 4 固定バージョン
    case opus4(version: String)

    /// Claude Sonnet 4 固定バージョン
    case sonnet4(version: String)

    // MARK: - Custom

    /// カスタムモデルID
    case custom(String)

    // MARK: - Model ID

    /// Extended Thinking をサポートするか
    ///
    /// Haiku モデルは Extended Thinking に非対応です。
    /// カスタムモデルは安全側で `true`（API が弾けば分かる）。
    public var supportsExtendedThinking: Bool {
        switch self {
        case .haiku, .haiku4_5:
            return false
        case .opus, .sonnet, .opus4_6, .sonnet4_6, .opus4_5, .sonnet4_5,
             .opus4_1, .opus4, .sonnet4:
            return true
        case .custom:
            return true
        }
    }

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .opus:
            return "claude-opus-4-6"
        case .sonnet:
            return "claude-sonnet-4-6"
        case .haiku:
            return "claude-haiku-4-5"
        case .opus4_6(let version):
            return "claude-opus-4-6-\(version)"
        case .sonnet4_6(let version):
            return "claude-sonnet-4-6-\(version)"
        case .opus4_5(let version):
            return "claude-opus-4-5-\(version)"
        case .sonnet4_5(let version):
            return "claude-sonnet-4-5-\(version)"
        case .haiku4_5(let version):
            return "claude-haiku-4-5-\(version)"
        case .opus4_1(let version):
            return "claude-opus-4-1-\(version)"
        case .opus4(let version):
            return "claude-opus-4-\(version)"
        case .sonnet4(let version):
            return "claude-sonnet-4-\(version)"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension ClaudeModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// Claude Opus 4.6（最高性能）
        case opus = "opus"
        /// Claude Sonnet 4.6（バランス型）
        case sonnet = "sonnet"
        /// Claude Haiku 4.5（高速・低コスト）
        case haiku = "haiku"

        public var id: String { rawValue }

        /// 対応する `ClaudeModel` を取得
        public var model: ClaudeModel {
            switch self {
            case .opus: return .opus
            case .sonnet: return .sonnet
            case .haiku: return .haiku
            }
        }

        /// 表示名
        public var displayName: String {
            switch self {
            case .opus: return "Claude Opus 4.6"
            case .sonnet: return "Claude Sonnet 4.6"
            case .haiku: return "Claude Haiku 4.5"
            }
        }

        /// 短い表示名
        public var shortName: String {
            switch self {
            case .opus: return "Opus"
            case .sonnet: return "Sonnet"
            case .haiku: return "Haiku"
            }
        }
    }
}
