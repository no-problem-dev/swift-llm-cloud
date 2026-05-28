import Foundation
import LLMClient

/// Groq モデル（ホステッドモデル）
public enum GroqModel: Sendable, Equatable {
    /// Llama 4 Scout 17B
    case llama4Scout

    /// Llama 3.3 70B Versatile
    case llama3_3_70b

    /// Llama 3.1 8B Instant
    case llama3_1_8b

    /// Qwen QwQ 32B
    case qwq32b

    /// Mistral Saba 24B
    case mistralSaba

    /// カスタムモデルID
    case custom(String)

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .llama4Scout:
            return "meta-llama/llama-4-scout-17b-16e-instruct"
        case .llama3_3_70b:
            return "llama-3.3-70b-versatile"
        case .llama3_1_8b:
            return "llama-3.1-8b-instant"
        case .qwq32b:
            return "qwen-qwq-32b"
        case .mistralSaba:
            return "mistral-saba-24b"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension GroqModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        /// Llama 4 Scout 17B
        case llama4Scout = "llama4Scout"
        /// Llama 3.3 70B Versatile
        case llama3_3_70b = "llama3_3_70b"
        /// Llama 3.1 8B Instant
        case llama3_1_8b = "llama3_1_8b"
        /// Qwen QwQ 32B
        case qwq32b = "qwq32b"
        /// Mistral Saba 24B
        case mistralSaba = "mistralSaba"

        public var id: String { rawValue }

        /// 対応する `GroqModel` を取得
        public var model: GroqModel {
            switch self {
            case .llama4Scout: return .llama4Scout
            case .llama3_3_70b: return .llama3_3_70b
            case .llama3_1_8b: return .llama3_1_8b
            case .qwq32b: return .qwq32b
            case .mistralSaba: return .mistralSaba
            }
        }

        /// 表示名
        public var displayName: String {
            switch self {
            case .llama4Scout: return "Llama 4 Scout 17B"
            case .llama3_3_70b: return "Llama 3.3 70B"
            case .llama3_1_8b: return "Llama 3.1 8B"
            case .qwq32b: return "QwQ 32B"
            case .mistralSaba: return "Mistral Saba 24B"
            }
        }

        /// 短い表示名
        public var shortName: String {
            switch self {
            case .llama4Scout: return "Scout"
            case .llama3_3_70b: return "70B"
            case .llama3_1_8b: return "8B"
            case .qwq32b: return "QwQ"
            case .mistralSaba: return "Saba"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .llama4Scout:
                return ModelProfile(
                    summary: "最新 Llama 4。高品質推論",
                    modelFamily: "Llama",
                    description: "Llama 4 Scout 17B は Meta の最新モデルを Groq の高速推論エンジンで提供します。16 エキスパートの MoE アーキテクチャにより高品質な応答を実現。",
                    contextWindow: 131_072,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-03",
                    strengths: ["最新アーキテクチャ", "MoE", "高品質推論", "超高速推論"],
                    bestFor: ["汎用チャット", "コード生成", "高速処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.11, outputPerMTok: 0.34)
                )
            case .llama3_3_70b:
                return ModelProfile(
                    summary: "高性能 70B。バランスの良い選択",
                    modelFamily: "Llama",
                    description: "Llama 3.3 70B Versatile は高性能と汎用性のバランスに優れたモデルです。Groq の超低レイテンシ推論で高速に利用可能。",
                    contextWindow: 128_000,
                    maxOutputTokens: 32_768,
                    knowledgeCutoff: "2024-12",
                    strengths: ["汎用性", "高品質", "ツール呼び出し", "超高速推論"],
                    bestFor: ["汎用タスク", "ツール利用エージェント", "コード生成"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.59, outputPerMTok: 0.79)
                )
            case .llama3_1_8b:
                return ModelProfile(
                    summary: "超高速 8B。最低レイテンシ",
                    modelFamily: "Llama",
                    description: "Llama 3.1 8B Instant は最も軽量で高速なモデルです。Groq 上で最低レイテンシを実現し、シンプルなタスクに最適。",
                    contextWindow: 128_000,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2024-12",
                    strengths: ["超低レイテンシ", "軽量", "低コスト", "高速応答"],
                    bestFor: ["シンプルなチャット", "分類タスク", "大量バッチ処理"],
                    toolCallSupport: .basic,
                    japaneseSupport: .basic,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.05, outputPerMTok: 0.08)
                )
            case .qwq32b:
                return ModelProfile(
                    summary: "推論特化。数学・科学に強い",
                    modelFamily: "Qwen",
                    description: "QwQ 32B は Qwen の推論特化モデルを Groq で高速実行するものです。数学・科学・論理的推論に優れた性能を発揮します。",
                    contextWindow: 131_072,
                    maxOutputTokens: 131_072,
                    knowledgeCutoff: "2025-01",
                    strengths: ["推論特化", "数学・科学", "論理的思考", "高速推論"],
                    bestFor: ["数学的推論", "科学的分析", "論理パズル"],
                    toolCallSupport: .basic,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.29, outputPerMTok: 0.39)
                )
            case .mistralSaba:
                return ModelProfile(
                    summary: "多言語対応。コスト効率良好",
                    modelFamily: "Mistral",
                    description: "Mistral Saba 24B は多言語対応に優れたモデルを Groq で高速実行するものです。コスト効率が良く、多言語タスクに適しています。",
                    contextWindow: 32_768,
                    maxOutputTokens: 8_192,
                    knowledgeCutoff: "2025-01",
                    strengths: ["多言語対応", "コスト効率", "高速推論", "汎用"],
                    bestFor: ["多言語チャット", "翻訳タスク", "コスト重視の処理"],
                    toolCallSupport: .basic,
                    japaneseSupport: .good,
                    modalities: [.text, .code],
                    pricing: .flat(inputPerMTok: 0.20, outputPerMTok: 0.60)
                )
            }
        }
    }
}
