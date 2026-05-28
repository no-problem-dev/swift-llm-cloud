import Foundation
import LLMClient

// MARK: - GPT Models

/// OpenAI GPT モデル
public enum GPTModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)

    case gpt5_5
    case gpt5_5Pro
    case gpt5_4
    case gpt5_4Mini
    case gpt5_4Nano
    case gpt5_4Pro
    case gpt5_2Codex
    case gpt5_2
    case gpt5_1
    case gpt5
    case gpt5Mini
    case gpt5Nano
    case gpt4_1
    case gpt4_1Mini
    case gpt4_1Nano
    case gpt4o
    case gpt4oMini
    case o1
    case o1Pro
    case o3
    case o3Pro
    case o3Mini
    case o4Mini

    // MARK: - Fixed Versions

    case gpt5_5_version(String)
    case gpt5_4_version(String)
    case gpt5_4Mini_version(String)
    case gpt5_4Nano_version(String)
    case gpt5_2_version(String)
    case gpt5_2Codex_version(String)
    case gpt5_1_version(String)
    case gpt5_version(String)
    case gpt5Mini_version(String)
    case gpt5Nano_version(String)
    case gpt4_1_version(String)
    case gpt4_1Mini_version(String)
    case gpt4_1Nano_version(String)
    case gpt4o_version(String)
    case gpt4oMini_version(String)
    case o1_version(String)
    case o3_version(String)
    case o3Mini_version(String)
    case o4Mini_version(String)

    // MARK: - Custom

    case custom(String)

    /// `reasoning_effort` パラメータを受け付けるか。
    /// 受け付けないモデルにこのパラメータを送るとリクエストが弾かれる。
    /// 対象: o-series (o1, o3, o3-pro, o3-mini, o4-mini) と GPT-5 系全部。
    public var supportsReasoningEffort: Bool {
        switch self {
        case .o1, .o1Pro, .o3, .o3Pro, .o3Mini, .o4Mini,
             .o1_version, .o3_version, .o3Mini_version, .o4Mini_version:
            return true
        case .gpt5_5, .gpt5_5Pro, .gpt5_4, .gpt5_4Mini, .gpt5_4Nano, .gpt5_4Pro,
             .gpt5_2Codex, .gpt5_2, .gpt5_1, .gpt5, .gpt5Mini, .gpt5Nano,
             .gpt5_5_version, .gpt5_4_version, .gpt5_4Mini_version, .gpt5_4Nano_version,
             .gpt5_2_version, .gpt5_2Codex_version, .gpt5_1_version, .gpt5_version,
             .gpt5Mini_version, .gpt5Nano_version:
            return true
        case .gpt4_1, .gpt4_1Mini, .gpt4_1Nano, .gpt4o, .gpt4oMini,
             .gpt4_1_version, .gpt4_1Mini_version, .gpt4_1Nano_version,
             .gpt4o_version, .gpt4oMini_version:
            return false
        case .custom:
            return false
        }
    }

    /// `reasoning_effort` で `.minimal` を許容するか。
    /// GPT-5 系のみ minimal を受け付ける。o-series は minimal 非対応。
    public var supportsMinimalReasoningEffort: Bool {
        switch self {
        case .gpt5_5, .gpt5_5Pro, .gpt5_4, .gpt5_4Mini, .gpt5_4Nano, .gpt5_4Pro,
             .gpt5_2Codex, .gpt5_2, .gpt5_1, .gpt5, .gpt5Mini, .gpt5Nano,
             .gpt5_5_version, .gpt5_4_version, .gpt5_4Mini_version, .gpt5_4Nano_version,
             .gpt5_2_version, .gpt5_2Codex_version, .gpt5_1_version, .gpt5_version,
             .gpt5Mini_version, .gpt5Nano_version:
            return true
        default:
            return false
        }
    }

    public var id: String {
        switch self {
        case .gpt5_5: return "gpt-5.5"
        case .gpt5_5Pro: return "gpt-5.5-pro"
        case .gpt5_4: return "gpt-5.4"
        case .gpt5_4Mini: return "gpt-5.4-mini"
        case .gpt5_4Nano: return "gpt-5.4-nano"
        case .gpt5_4Pro: return "gpt-5.4-pro"
        case .gpt5_2Codex: return "gpt-5.2-codex"
        case .gpt5_2: return "gpt-5.2"
        case .gpt5_1: return "gpt-5.1"
        case .gpt5: return "gpt-5"
        case .gpt5Mini: return "gpt-5-mini"
        case .gpt5Nano: return "gpt-5-nano"
        case .gpt4_1: return "gpt-4.1"
        case .gpt4_1Mini: return "gpt-4.1-mini"
        case .gpt4_1Nano: return "gpt-4.1-nano"
        case .gpt4o: return "gpt-4o"
        case .gpt4oMini: return "gpt-4o-mini"
        case .o1: return "o1"
        case .o1Pro: return "o1-pro"
        case .o3: return "o3"
        case .o3Pro: return "o3-pro"
        case .o3Mini: return "o3-mini"
        case .o4Mini: return "o4-mini"
        case .gpt5_5_version(let v): return "gpt-5.5-\(v)"
        case .gpt5_4_version(let v): return "gpt-5.4-\(v)"
        case .gpt5_4Mini_version(let v): return "gpt-5.4-mini-\(v)"
        case .gpt5_4Nano_version(let v): return "gpt-5.4-nano-\(v)"
        case .gpt5_2_version(let v): return "gpt-5.2-\(v)"
        case .gpt5_2Codex_version(let v): return "gpt-5.2-codex-\(v)"
        case .gpt5_1_version(let v): return "gpt-5.1-\(v)"
        case .gpt5_version(let v): return "gpt-5-\(v)"
        case .gpt5Mini_version(let v): return "gpt-5-mini-\(v)"
        case .gpt5Nano_version(let v): return "gpt-5-nano-\(v)"
        case .gpt4_1_version(let v): return "gpt-4.1-\(v)"
        case .gpt4_1Mini_version(let v): return "gpt-4.1-mini-\(v)"
        case .gpt4_1Nano_version(let v): return "gpt-4.1-nano-\(v)"
        case .gpt4o_version(let v): return "gpt-4o-\(v)"
        case .gpt4oMini_version(let v): return "gpt-4o-mini-\(v)"
        case .o1_version(let v): return "o1-\(v)"
        case .o3_version(let v): return "o3-\(v)"
        case .o3Mini_version(let v): return "o3-mini-\(v)"
        case .o4Mini_version(let v): return "o4-mini-\(v)"
        case .custom(let id): return id
        }
    }
}

// MARK: - Preset

extension GPTModel {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case gpt5_5 = "gpt5_5"
        case gpt5_4 = "gpt5_4"
        case gpt5_4Mini = "gpt5_4Mini"
        case o3 = "o3"
        case o4Mini = "o4Mini"
        case gpt5_2Codex = "gpt5_2Codex"

        public var id: String { rawValue }

        public var model: GPTModel {
            switch self {
            case .gpt5_5: return .gpt5_5
            case .gpt5_4: return .gpt5_4
            case .gpt5_4Mini: return .gpt5_4Mini
            case .o3: return .o3
            case .o4Mini: return .o4Mini
            case .gpt5_2Codex: return .gpt5_2Codex
            }
        }

        public var displayName: String {
            switch self {
            case .gpt5_5: return "GPT-5.5"
            case .gpt5_4: return "GPT-5.4"
            case .gpt5_4Mini: return "GPT-5.4 mini"
            case .o3: return "o3"
            case .o4Mini: return "o4-mini"
            case .gpt5_2Codex: return "GPT-5.2 Codex"
            }
        }

        public var shortName: String {
            switch self {
            case .gpt5_5: return "5.5"
            case .gpt5_4: return "5.4"
            case .gpt5_4Mini: return "5.4-mini"
            case .o3: return "o3"
            case .o4Mini: return "o4-mini"
            case .gpt5_2Codex: return "5.2-codex"
            }
        }

        public var profile: ModelProfile {
            switch self {
            case .gpt5_5:
                return ModelProfile(
                    summary: "現フラッグシップ。最高品質のマルチモーダル推論",
                    modelFamily: "GPT",
                    description: "GPT-5.5 は OpenAI の最新フラッグシップ。GPT-5.4 から 6 週間で投入されたモデルで、入力 $5 / 出力 $30 と単価は倍増したが、より少ないトークンで応答する設計。",
                    contextWindow: 400_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2026-03",
                    strengths: ["最高品質の推論", "マルチモーダル", "ツール呼び出し", "エージェント性能"],
                    bestFor: ["最高品質を要する分析", "重要なエージェントタスク", "プロダクション応答"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio],
                    pricing: .flat(inputPerMTok: 5, outputPerMTok: 30, cacheReadPerMTok: 0.50)
                )
            case .gpt5_4:
                return ModelProfile(
                    summary: "コストフロンティア。バランス重視の汎用モデル",
                    modelFamily: "GPT",
                    description: "GPT-5.4 は GPT-5.5 と並ぶ現行ファミリーのコスト効率版。$2.50 / $15 の単価で汎用タスクに広く適合。",
                    contextWindow: 400_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2026-01",
                    strengths: ["汎用性", "コスト効率", "ツール呼び出し", "適応的推論"],
                    bestFor: ["汎用エージェント", "中規模分析", "コスト重視のプロダクション"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio],
                    pricing: .flat(inputPerMTok: 2.50, outputPerMTok: 15, cacheReadPerMTok: 0.25)
                )
            case .gpt5_4Mini:
                return ModelProfile(
                    summary: "軽量版 5.4。コスト最重視タスクに",
                    modelFamily: "GPT",
                    description: "GPT-5.4 mini は GPT-5.4 の軽量バリアント。$0.75 / $4.50 の単価で高スループットなタスクに適合。",
                    contextWindow: 400_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2026-01",
                    strengths: ["低コスト", "高スループット", "汎用性"],
                    bestFor: ["大量バッチ", "分類", "簡易チャット"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 0.75, outputPerMTok: 4.50, cacheReadPerMTok: 0.075)
                )
            case .o3:
                return ModelProfile(
                    summary: "高度な推論特化。数学・科学・コーディングに最適",
                    modelFamily: "o-series",
                    description: "o3 は数学・科学・コーディングで標準を確立した推論特化モデル。10 万トークンの出力で詳細な推論チェーンを生成する。",
                    contextWindow: 200_000,
                    maxOutputTokens: 100_000,
                    knowledgeCutoff: "2024-06",
                    strengths: ["高度な推論", "数学・科学", "技術的ライティング", "視覚的推論"],
                    bestFor: ["数学・科学の問題解決", "多段階コーディング", "技術分析"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 2, outputPerMTok: 8, cacheReadPerMTok: 0.50)
                )
            case .o4Mini:
                return ModelProfile(
                    summary: "軽量推論。高速かつ低コスト",
                    modelFamily: "o-series",
                    description: "o4-mini は高速かつコスト効率の良い推論モデル。AIME 数学ベンチマークでトップクラスの性能を発揮し、o3 よりも低コストで推論タスクを処理できる。",
                    contextWindow: 200_000,
                    maxOutputTokens: 100_000,
                    knowledgeCutoff: "2024-06",
                    strengths: ["高速推論", "コスト効率", "数学ベンチマーク高性能", "コーディング"],
                    bestFor: ["大量推論タスク", "高速な数学・コード処理", "コスト効率重視の推論"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: .flat(inputPerMTok: 0.55, outputPerMTok: 2.20, cacheReadPerMTok: 0.138)
                )
            case .gpt5_2Codex:
                return ModelProfile(
                    summary: "コーディング特化。コード生成・修正に最適化",
                    modelFamily: "GPT",
                    description: "GPT-5.2 Codex は OpenAI のコーディング専用モデル。$1.75 / $14 の単価でコード生成、リファクタリング、コードレビューに最適化されている。",
                    contextWindow: 400_000,
                    maxOutputTokens: 128_000,
                    knowledgeCutoff: "2025-08",
                    strengths: ["コード生成", "コードレビュー", "リファクタリング", "デバッグ"],
                    bestFor: ["コーディングエージェント", "コード解析", "大規模リファクタリング"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 1.75, outputPerMTok: 14, cacheReadPerMTok: 0.175)
                )
            }
        }
    }
}
