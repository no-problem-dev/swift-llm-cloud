import Foundation
import LLMClient

/// DeepSeek モデル
public enum DeepSeekModel: Sendable, Equatable {
    /// DeepSeek-V3 最新版
    case v3

    /// DeepSeek-R1 最新版（推論特化）
    case r1

    /// DeepSeek-R1-0528 バージョン
    case r1_0528

    /// カスタムモデルID
    case custom(String)

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .v3:
            return "deepseek-chat"
        case .r1:
            return "deepseek-reasoner"
        case .r1_0528:
            return "deepseek-r1-0528"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension DeepSeekModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// DeepSeek-V3（汎用チャット）
        case v3 = "v3"
        /// DeepSeek-R1（推論特化）
        case r1 = "r1"
        /// DeepSeek-R1-0528（推論特化・固定版）
        case r1_0528 = "r1_0528"

        public var id: String { rawValue }

        /// 対応する `DeepSeekModel` を取得
        public var model: DeepSeekModel {
            switch self {
            case .v3: return .v3
            case .r1: return .r1
            case .r1_0528: return .r1_0528
            }
        }

        /// 表示名
        public var displayName: String {
            switch self {
            case .v3: return "DeepSeek-V3"
            case .r1: return "DeepSeek-R1"
            case .r1_0528: return "DeepSeek-R1-0528"
            }
        }

        /// 短い表示名
        public var shortName: String {
            switch self {
            case .v3: return "V3"
            case .r1: return "R1"
            case .r1_0528: return "R1-0528"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .v3:
                return ModelProfile(
                    summary: "汎用チャット。高いコスト効率",
                    modelFamily: "DeepSeek",
                    description: "DeepSeek-V3 は DeepSeek の最新汎用モデルです。高品質なテキスト生成とコーディングを低コストで提供し、多くの一般的なタスクに適しています。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-03",
                    strengths: ["高いコスト効率", "汎用チャット", "コーディング", "多言語対応"],
                    bestFor: ["汎用チャット", "コード生成", "コスト重視のタスク"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: Pricing(inputPerMTok: 0.27, outputPerMTok: 1.10)
                )
            case .r1:
                return ModelProfile(
                    summary: "推論特化。深い思考が可能",
                    modelFamily: "DeepSeek",
                    description: "DeepSeek-R1 は推論に特化したモデルです。Chain-of-Thought による深い推論が可能で、数学・科学・コーディングの複雑な問題に優れた性能を発揮します。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-03",
                    strengths: ["深い推論", "数学・科学", "Chain-of-Thought", "コーディング"],
                    bestFor: ["数学的推論", "科学的分析", "複雑な問題解決"],
                    toolCallSupport: .basic,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: Pricing(inputPerMTok: 0.55, outputPerMTok: 2.19)
                )
            case .r1_0528:
                return ModelProfile(
                    summary: "推論特化・固定版。安定した推論品質",
                    modelFamily: "DeepSeek",
                    description: "DeepSeek-R1-0528 は R1 の固定バージョンです。安定した推論品質を提供し、再現性が求められるタスクに適しています。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-03",
                    strengths: ["安定した推論", "再現性", "数学・科学", "コーディング"],
                    bestFor: ["再現性が必要な推論タスク", "ベンチマーク比較", "安定した品質が必要なタスク"],
                    toolCallSupport: .basic,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: Pricing(inputPerMTok: 0.55, outputPerMTok: 2.19)
                )
            }
        }
    }
}
