import Foundation
import LLMClient

/// xAI Grok モデル
public enum GrokModel: Sendable, Equatable {
    /// Grok 3 最新版
    case grok3

    /// Grok 3 Mini（軽量版）
    case grok3Mini

    /// Grok 3 Fast（高速版）
    case grok3Fast

    /// Grok 3 Mini Fast（軽量高速版）
    case grok3MiniFast

    /// カスタムモデルID
    case custom(String)

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .grok3:
            return "grok-3"
        case .grok3Mini:
            return "grok-3-mini"
        case .grok3Fast:
            return "grok-3-fast"
        case .grok3MiniFast:
            return "grok-3-mini-fast"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension GrokModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// Grok 3（フラッグシップ）
        case grok3 = "grok3"
        /// Grok 3 Mini（軽量版）
        case grok3Mini = "grok3Mini"
        /// Grok 3 Fast（高速版）
        case grok3Fast = "grok3Fast"
        /// Grok 3 Mini Fast（軽量高速版）
        case grok3MiniFast = "grok3MiniFast"

        public var id: String { rawValue }

        /// 対応する `GrokModel` を取得
        public var model: GrokModel {
            switch self {
            case .grok3: return .grok3
            case .grok3Mini: return .grok3Mini
            case .grok3Fast: return .grok3Fast
            case .grok3MiniFast: return .grok3MiniFast
            }
        }

        /// 表示名
        public var displayName: String {
            switch self {
            case .grok3: return "Grok 3"
            case .grok3Mini: return "Grok 3 Mini"
            case .grok3Fast: return "Grok 3 Fast"
            case .grok3MiniFast: return "Grok 3 Mini Fast"
            }
        }

        /// 短い表示名
        public var shortName: String {
            switch self {
            case .grok3: return "3"
            case .grok3Mini: return "3 Mini"
            case .grok3Fast: return "3 Fast"
            case .grok3MiniFast: return "3 Mini Fast"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .grok3:
                return ModelProfile(
                    summary: "xAI フラッグシップ。高度な推論",
                    modelFamily: "Grok",
                    description: "Grok 3 は xAI のフラッグシップモデルです。高度な推論能力と幅広い知識を持ち、複雑なタスクに対応します。",
                    contextWindow: 131_072,
                    maxOutputTokens: 131_072,
                    knowledgeCutoff: "2025-03",
                    strengths: ["高度な推論", "幅広い知識", "コーディング", "分析"],
                    bestFor: ["複雑な推論タスク", "コード生成", "詳細な分析"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 3, outputPerMTok: 15)
                )
            case .grok3Mini:
                return ModelProfile(
                    summary: "軽量版。高速応答でコスト効率良好",
                    modelFamily: "Grok",
                    description: "Grok 3 Mini は Grok 3 の軽量版で、高速な応答とコスト効率に優れています。一般的なタスクに最適です。",
                    contextWindow: 131_072,
                    maxOutputTokens: 131_072,
                    knowledgeCutoff: "2025-03",
                    strengths: ["高速応答", "コスト効率", "軽量", "汎用"],
                    bestFor: ["汎用チャット", "簡単なコード生成", "大量処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.30, outputPerMTok: 0.50)
                )
            case .grok3Fast:
                return ModelProfile(
                    summary: "高速版。低レイテンシの推論",
                    modelFamily: "Grok",
                    description: "Grok 3 Fast は Grok 3 の高速バリアントで、低レイテンシで高品質な応答を提供します。",
                    contextWindow: 131_072,
                    maxOutputTokens: 131_072,
                    knowledgeCutoff: "2025-03",
                    strengths: ["低レイテンシ", "高品質応答", "リアルタイム処理", "推論"],
                    bestFor: ["リアルタイムアプリケーション", "高速な推論", "インタラクティブなタスク"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 5, outputPerMTok: 25)
                )
            case .grok3MiniFast:
                return ModelProfile(
                    summary: "最速・最安。軽量タスクに最適",
                    modelFamily: "Grok",
                    description: "Grok 3 Mini Fast は最速かつ最もコスト効率の良い Grok モデルです。軽量なタスクや大量処理に適しています。",
                    contextWindow: 131_072,
                    maxOutputTokens: 131_072,
                    knowledgeCutoff: "2025-03",
                    strengths: ["最速", "最低コスト", "大量処理向き", "軽量"],
                    bestFor: ["軽量タスク", "大量バッチ処理", "プロトタイピング"],
                    toolCallSupport: .good,
                    japaneseSupport: .basic,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.06, outputPerMTok: 0.10)
                )
            }
        }
    }
}
