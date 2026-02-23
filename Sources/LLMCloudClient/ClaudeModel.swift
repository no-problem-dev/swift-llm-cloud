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
///     model: .sonnet4_5("20250929")  // 特定バージョンを指定
/// )
/// ```
///
/// ## カスタムモデルID
/// ```swift
/// let result: UserInfo = try await client.generate(
///     input: "...",
///     model: .custom("claude-3-opus-20240229")  // 任意のモデルID
/// )
/// ```
public enum ClaudeModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)

    /// Claude Opus 4.5 最新版（最高性能）
    case opus

    /// Claude Sonnet 4.5 最新版（バランス型）
    case sonnet

    /// Claude Haiku 4.5 最新版（高速・低コスト）
    case haiku

    // MARK: - Fixed Versions

    /// Claude Opus 4.5 固定バージョン
    /// - Parameter version: バージョン文字列（例: "20251101"）
    case opus4_5(version: String)

    /// Claude Sonnet 4.5 固定バージョン
    /// - Parameter version: バージョン文字列（例: "20250929"）
    case sonnet4_5(version: String)

    /// Claude Haiku 4.5 固定バージョン
    /// - Parameter version: バージョン文字列（例: "20250929"）
    case haiku4_5(version: String)

    /// Claude Opus 4.1 固定バージョン
    /// - Parameter version: バージョン文字列（例: "20250918"）
    case opus4_1(version: String)

    /// Claude Sonnet 4 固定バージョン
    /// - Parameter version: バージョン文字列（例: "20250514"）
    case sonnet4(version: String)

    // MARK: - Custom

    /// カスタムモデルID
    /// - Parameter id: 任意のモデルID文字列
    case custom(String)

    // MARK: - Model ID

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        // Aliases（常に最新のスナップショットを指す）
        case .opus:
            return "claude-opus-4-5"
        case .sonnet:
            return "claude-sonnet-4-5"
        case .haiku:
            return "claude-haiku-4-5"
        // Fixed versions
        case .opus4_5(let version):
            return "claude-opus-4-5-\(version)"
        case .sonnet4_5(let version):
            return "claude-sonnet-4-5-\(version)"
        case .haiku4_5(let version):
            return "claude-haiku-4-5-\(version)"
        case .opus4_1(let version):
            return "claude-opus-4-1-\(version)"
        case .sonnet4(let version):
            return "claude-sonnet-4-\(version)"
        // Custom
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension ClaudeModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// Claude Opus 4.5（最高性能）
        case opus = "opus"
        /// Claude Sonnet 4.5（バランス型）
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
            case .opus: return "Claude Opus 4.5"
            case .sonnet: return "Claude Sonnet 4.5"
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
