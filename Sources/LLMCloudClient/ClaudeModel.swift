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

    /// Claude Opus 最新版（最高性能 / 現フラッグシップ = Opus 4.7）
    case opus

    /// Claude Sonnet 最新版（バランス型 / 現行 = Sonnet 4.6）
    case sonnet

    /// Claude Haiku 最新版（高速・低コスト / 現行 = Haiku 4.5）
    case haiku

    // MARK: - Dateless Snapshots (4.6 generation onward)

    /// Claude Opus 4.7（dateless = pinned snapshot）
    case opus4_7

    /// Claude Opus 4.6（dateless）
    case opus4_6

    /// Claude Sonnet 4.6（dateless）
    case sonnet4_6

    // MARK: - Aliased Versions (4.5 generation, dated under the hood)

    /// Claude Opus 4.5 alias
    case opus4_5

    /// Claude Sonnet 4.5 alias
    case sonnet4_5

    /// Claude Haiku 4.5 alias
    case haiku4_5

    // MARK: - Fixed Versions

    case opus4_7_version(String)
    case opus4_6_version(String)
    case sonnet4_6_version(String)
    case opus4_5_version(String)
    case sonnet4_5_version(String)
    case haiku4_5_version(String)
    case opus4_1_version(String)
    case opus4_version(String)
    case sonnet4_version(String)

    // MARK: - Custom

    case custom(String)

    // MARK: - Model ID

    /// Extended Thinking をサポートするか。
    /// Opus 4.7 は Adaptive Thinking のみ（Extended Thinking 非対応）。Haiku は非対応。
    public var supportsExtendedThinking: Bool {
        switch self {
        case .opus, .opus4_7, .opus4_7_version:
            return false
        case .haiku, .haiku4_5, .haiku4_5_version:
            return false
        case .sonnet, .sonnet4_6, .sonnet4_6_version,
             .opus4_6, .opus4_6_version,
             .opus4_5, .opus4_5_version,
             .sonnet4_5, .sonnet4_5_version,
             .opus4_1_version,
             .opus4_version, .sonnet4_version:
            return true
        case .custom:
            return true
        }
    }

    public var id: String {
        switch self {
        case .opus, .opus4_7:
            return "claude-opus-4-7"
        case .sonnet, .sonnet4_6:
            return "claude-sonnet-4-6"
        case .haiku, .haiku4_5:
            return "claude-haiku-4-5"
        case .opus4_6:
            return "claude-opus-4-6"
        case .opus4_5:
            return "claude-opus-4-5"
        case .sonnet4_5:
            return "claude-sonnet-4-5"
        case .opus4_7_version(let version):
            return "claude-opus-4-7-\(version)"
        case .opus4_6_version(let version):
            return "claude-opus-4-6-\(version)"
        case .sonnet4_6_version(let version):
            return "claude-sonnet-4-6-\(version)"
        case .opus4_5_version(let version):
            return "claude-opus-4-5-\(version)"
        case .sonnet4_5_version(let version):
            return "claude-sonnet-4-5-\(version)"
        case .haiku4_5_version(let version):
            return "claude-haiku-4-5-\(version)"
        case .opus4_1_version(let version):
            return "claude-opus-4-1-\(version)"
        case .opus4_version(let version):
            return "claude-opus-4-\(version)"
        case .sonnet4_version(let version):
            return "claude-sonnet-4-\(version)"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension ClaudeModel {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case opus = "opus"
        case sonnet = "sonnet"
        case haiku = "haiku"

        public var id: String { rawValue }

        public var model: ClaudeModel {
            switch self {
            case .opus: return .opus
            case .sonnet: return .sonnet
            case .haiku: return .haiku
            }
        }

        public var displayName: String {
            switch self {
            case .opus: return "Claude Opus 4.7"
            case .sonnet: return "Claude Sonnet 4.6"
            case .haiku: return "Claude Haiku 4.5"
            }
        }

        public var shortName: String {
            switch self {
            case .opus: return "Opus"
            case .sonnet: return "Sonnet"
            case .haiku: return "Haiku"
            }
        }

        public var profile: ModelProfile {
            switch self {
            case .opus:
                return ModelProfile(
                    summary: "最高性能。複雑な推論・コード生成に最適",
                    modelFamily: "Claude",
                    description: "Claude Opus 4.7 は Anthropic の現フラッグシップ。複雑な多段階推論、高度なコード生成、エージェントワークフローに優れる。1M トークンの context window と 128K の出力に対応。Adaptive Thinking で複雑度に応じて計算リソースを自動配分。新トークナイザを採用しており、同じテキストでも 4.6 比で最大 35% トークンが増える場合がある。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2026-01",
                    strengths: ["複雑な推論", "コード生成", "エージェント構築", "Adaptive Thinking", "超大容量コンテキスト"],
                    bestFor: ["エージェントワークフロー", "複雑な分析・推論", "長文コード生成"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(
                        inputPerMTok: 5,
                        outputPerMTok: 25,
                        cacheReadPerMTok: 0.50,
                        cacheWriteShortPerMTok: 6.25,
                        cacheWriteLongPerMTok: 10
                    )
                )
            case .sonnet:
                return ModelProfile(
                    summary: "バランス型。速度と品質の最適なトレードオフ",
                    modelFamily: "Claude",
                    description: "Claude Sonnet 4.6 は速度と知性の最適バランスを実現するモデル。1M トークンの context window、Extended Thinking と Adaptive Thinking の両方に対応。",
                    contextWindow: 1_000_000,
                    maxOutputTokens: 64_000,
                    knowledgeCutoff: "2025-08",
                    strengths: ["速度と品質のバランス", "コーディング", "超大容量コンテキスト", "Extended Thinking"],
                    bestFor: ["高スループット分析", "コーディングタスク", "コスト効率重視の汎用タスク"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(
                        inputPerMTok: 3,
                        outputPerMTok: 15,
                        cacheReadPerMTok: 0.30,
                        cacheWriteShortPerMTok: 3.75,
                        cacheWriteLongPerMTok: 6
                    )
                )
            case .haiku:
                return ModelProfile(
                    summary: "高速・低コスト。軽量タスクに最適",
                    modelFamily: "Claude",
                    description: "Claude Haiku 4.5 は最速の Claude モデルで、フロンティアに近い知性を低コストで提供する。リアルタイムチャットや大量処理に最適。",
                    contextWindow: 200_000,
                    maxOutputTokens: 64_000,
                    knowledgeCutoff: "2025-02",
                    strengths: ["高速応答", "低コスト", "大量処理向き"],
                    bestFor: ["リアルタイムチャット", "大量バッチ処理", "コスト重視のアプリケーション"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(
                        inputPerMTok: 1,
                        outputPerMTok: 5,
                        cacheReadPerMTok: 0.10,
                        cacheWriteShortPerMTok: 1.25,
                        cacheWriteLongPerMTok: 2
                    )
                )
            }
        }
    }
}
