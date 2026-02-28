import Foundation
import LLMClient

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

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .opus:
                return ModelProfile(
                    summary: "最高性能。複雑な推論・コード生成に最適",
                    modelFamily: "Claude",
                    description: "Claude Opus 4.6 は Anthropic の最高性能モデルです。複雑な多段階推論、高度なコード生成、エージェントワークフローに優れています。128K トークンの出力に対応し、Extended Thinking による深い思考が可能です。",
                    contextWindow: 200_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2025-05",
                    strengths: ["複雑な推論", "コード生成", "エージェント構築", "Extended Thinking"],
                    bestFor: ["エージェントワークフロー", "複雑な分析・推論", "長文コード生成"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 15, outputPerMTok: 75, cacheInputPerMTok: 1.875)
                )
            case .sonnet:
                return ModelProfile(
                    summary: "バランス型。速度と品質の最適なトレードオフ",
                    modelFamily: "Claude",
                    description: "Claude Sonnet 4.6 は速度と知性の最適バランスを実現するモデルです。コーディングと分析に強く、Extended Thinking にも対応。Opus よりも低コストで多くのタスクに適しています。",
                    contextWindow: 200_000,
                    maxOutputTokens: 64_000,
                    knowledgeCutoff: "2025-08",
                    strengths: ["速度と品質のバランス", "コーディング", "最新の学習データ", "Extended Thinking"],
                    bestFor: ["高スループット分析", "コーディングタスク", "コスト効率重視の汎用タスク"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 3, outputPerMTok: 15, cacheInputPerMTok: 0.375)
                )
            case .haiku:
                return ModelProfile(
                    summary: "高速・低コスト。軽量タスクに最適",
                    modelFamily: "Claude",
                    description: "Claude Haiku 4.5 は最速の Claude モデルで、フロンティアに近い知性を低コストで提供します。リアルタイムチャットや大量処理に適しています。",
                    contextWindow: 200_000,
                    maxOutputTokens: 64_000,
                    knowledgeCutoff: "2025-02",
                    strengths: ["高速応答", "低コスト", "大量処理向き", "Extended Thinking 対応"],
                    bestFor: ["リアルタイムチャット", "大量バッチ処理", "コスト重視のアプリケーション"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 0.80, outputPerMTok: 4, cacheInputPerMTok: 0.08)
                )
            }
        }
    }
}
