import Foundation
import LLMClient

/// Mistral AI モデル
public enum MistralModel: Sendable, Equatable {
    /// Mistral Small（軽量版）
    case small

    /// Mistral Medium（中間版）
    case medium

    /// Mistral Large 最新版
    case large

    /// Codestral（コーディング特化）
    case codestral

    /// Mistral Nemo（軽量版）
    case nemo

    /// カスタムモデルID
    case custom(String)

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .small:
            return "mistral-small-latest"
        case .medium:
            return "mistral-medium-latest"
        case .large:
            return "mistral-large-latest"
        case .codestral:
            return "codestral-latest"
        case .nemo:
            return "open-mistral-nemo"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension MistralModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// Mistral Small（軽量版）
        case small = "small"
        /// Mistral Medium（中間版）
        case medium = "medium"
        /// Mistral Large（最高性能）
        case large = "large"
        /// Codestral（コーディング特化）
        case codestral = "codestral"
        /// Mistral Nemo（軽量版）
        case nemo = "nemo"

        public var id: String { rawValue }

        /// 対応する `MistralModel` を取得
        public var model: MistralModel {
            switch self {
            case .small: return .small
            case .medium: return .medium
            case .large: return .large
            case .codestral: return .codestral
            case .nemo: return .nemo
            }
        }

        /// 表示名
        public var displayName: String {
            switch self {
            case .small: return "Mistral Small"
            case .medium: return "Mistral Medium"
            case .large: return "Mistral Large"
            case .codestral: return "Codestral"
            case .nemo: return "Mistral Nemo"
            }
        }

        /// 短い表示名
        public var shortName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            case .codestral: return "Codestral"
            case .nemo: return "Nemo"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .small:
                return ModelProfile(
                    summary: "軽量・高速。コスト効率に優れる",
                    modelFamily: "Mistral",
                    description: "Mistral Small は軽量で高速なモデルです。一般的なタスクに十分な品質を低コストで提供し、大量処理やリアルタイムアプリケーションに適しています。",
                    contextWindow: 32_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-01",
                    strengths: ["軽量・高速", "コスト効率", "多言語対応", "関数呼び出し"],
                    bestFor: ["軽量チャット", "分類・要約", "大量バッチ処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.10, outputPerMTok: 0.30)
                )
            case .medium:
                return ModelProfile(
                    summary: "バランス型。品質と速度の両立",
                    modelFamily: "Mistral",
                    description: "Mistral Medium は品質と速度のバランスに優れたモデルです。多くのビジネスユースケースに適した汎用モデルです。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-01",
                    strengths: ["バランス型", "汎用性", "品質と速度の両立", "多言語"],
                    bestFor: ["ビジネスタスク", "コンテンツ生成", "分析・要約"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.40, outputPerMTok: 2)
                )
            case .large:
                return ModelProfile(
                    summary: "最高性能。複雑な推論に最適",
                    modelFamily: "Mistral",
                    description: "Mistral Large は Mistral の最高性能モデルです。複雑な推論、多段階分析、高度なコード生成に優れ、128K のコンテキストウィンドウを持ちます。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-01",
                    strengths: ["高度な推論", "多言語", "コーディング", "関数呼び出し"],
                    bestFor: ["複雑な推論", "コード生成", "多言語タスク"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 2, outputPerMTok: 6)
                )
            case .codestral:
                return ModelProfile(
                    summary: "コーディング特化。80+ 言語対応",
                    modelFamily: "Mistral",
                    description: "Codestral は Mistral のコーディング特化モデルです。80 以上のプログラミング言語に対応し、コード生成・補完・リファクタリングに特化しています。",
                    contextWindow: 256_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-01",
                    strengths: ["コーディング特化", "80+ 言語", "コード補完", "リファクタリング"],
                    bestFor: ["コード生成", "コードレビュー", "リファクタリング"],
                    toolCallSupport: .good,
                    japaneseSupport: .basic,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.30, outputPerMTok: 0.90)
                )
            case .nemo:
                return ModelProfile(
                    summary: "超軽量。エッジ・オンデバイス向け",
                    modelFamily: "Mistral",
                    description: "Mistral Nemo は超軽量モデルで、エッジデバイスやオンデバイス推論に適しています。シンプルなタスクを高速に処理します。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2024-07",
                    strengths: ["超軽量", "高速", "低コスト", "エッジ対応"],
                    bestFor: ["シンプルなチャット", "軽量な分類", "エッジ推論"],
                    toolCallSupport: .basic,
                    japaneseSupport: .basic,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.15, outputPerMTok: 0.15)
                )
            }
        }
    }
}
