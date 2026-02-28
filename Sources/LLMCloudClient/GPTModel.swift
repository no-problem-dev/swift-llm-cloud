import Foundation
import LLMClient

// MARK: - GPT Models

/// OpenAI GPT モデル
///
/// エイリアス（推奨）または固定バージョンでモデルを指定できます。
public enum GPTModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)

    /// GPT-5.2 最新版
    case gpt5_2

    /// GPT-5.1 最新版
    case gpt5_1

    /// GPT-5 最新版
    case gpt5

    /// GPT-5 mini 最新版
    case gpt5Mini

    /// GPT-4.1 最新版
    case gpt4_1

    /// GPT-4.1 mini 最新版
    case gpt4_1Mini

    /// GPT-4o 最新版（マルチモーダル）
    case gpt4o

    /// GPT-4o mini 最新版（軽量版）
    case gpt4oMini

    /// o1 最新版（推論特化）
    case o1

    /// o3 最新版（高度な推論）
    case o3

    /// o3-pro 最新版（プロ推論）
    case o3Pro

    /// o3-mini 最新版（軽量推論）
    case o3Mini

    /// o4-mini 最新版（最新軽量推論）
    case o4Mini

    // MARK: - Fixed Versions

    /// GPT-5.2 固定バージョン
    case gpt5_2_version(String)

    /// GPT-5.1 固定バージョン
    case gpt5_1_version(String)

    /// GPT-5 固定バージョン
    case gpt5_version(String)

    /// GPT-5 mini 固定バージョン
    case gpt5Mini_version(String)

    /// GPT-4.1 固定バージョン
    case gpt4_1_version(String)

    /// GPT-4.1 mini 固定バージョン
    case gpt4_1Mini_version(String)

    /// GPT-4o 固定バージョン
    case gpt4o_version(String)

    /// GPT-4o mini 固定バージョン
    case gpt4oMini_version(String)

    /// o1 固定バージョン
    case o1_version(String)

    /// o3 固定バージョン
    case o3_version(String)

    /// o3-mini 固定バージョン
    case o3Mini_version(String)

    /// o4-mini 固定バージョン
    case o4Mini_version(String)

    // MARK: - Custom

    /// カスタムモデルID
    case custom(String)

    // MARK: - Model ID

    /// モデルID文字列を取得
    public var id: String {
        switch self {
        case .gpt5_2:
            return "gpt-5.2"
        case .gpt5_1:
            return "gpt-5.1"
        case .gpt5:
            return "gpt-5"
        case .gpt5Mini:
            return "gpt-5-mini"
        case .gpt4_1:
            return "gpt-4.1"
        case .gpt4_1Mini:
            return "gpt-4.1-mini"
        case .gpt4o:
            return "gpt-4o"
        case .gpt4oMini:
            return "gpt-4o-mini"
        case .o1:
            return "o1"
        case .o3:
            return "o3"
        case .o3Pro:
            return "o3-pro"
        case .o3Mini:
            return "o3-mini"
        case .o4Mini:
            return "o4-mini"
        case .gpt5_2_version(let version):
            return "gpt-5.2-\(version)"
        case .gpt5_1_version(let version):
            return "gpt-5.1-\(version)"
        case .gpt5_version(let version):
            return "gpt-5-\(version)"
        case .gpt5Mini_version(let version):
            return "gpt-5-mini-\(version)"
        case .gpt4_1_version(let version):
            return "gpt-4.1-\(version)"
        case .gpt4_1Mini_version(let version):
            return "gpt-4.1-mini-\(version)"
        case .gpt4o_version(let version):
            return "gpt-4o-\(version)"
        case .gpt4oMini_version(let version):
            return "gpt-4o-mini-\(version)"
        case .o1_version(let version):
            return "o1-\(version)"
        case .o3_version(let version):
            return "o3-\(version)"
        case .o3Mini_version(let version):
            return "o3-mini-\(version)"
        case .o4Mini_version(let version):
            return "o4-mini-\(version)"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension GPTModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case gpt5_2 = "gpt5_2"
        case gpt4_1 = "gpt4_1"
        case o3 = "o3"
        case o4Mini = "o4Mini"

        public var id: String { rawValue }

        public var model: GPTModel {
            switch self {
            case .gpt5_2: return .gpt5_2
            case .gpt4_1: return .gpt4_1
            case .o3: return .o3
            case .o4Mini: return .o4Mini
            }
        }

        public var displayName: String {
            switch self {
            case .gpt5_2: return "GPT-5.2"
            case .gpt4_1: return "GPT-4.1"
            case .o3: return "o3"
            case .o4Mini: return "o4-mini"
            }
        }

        public var shortName: String {
            switch self {
            case .gpt5_2: return "5.2"
            case .gpt4_1: return "4.1"
            case .o3: return "o3"
            case .o4Mini: return "o4-mini"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .gpt5_2:
                return ModelProfile(
                    summary: "最新フラッグシップ。最高品質の推論",
                    modelFamily: "GPT",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio],
                    pricing: Pricing(inputPerMTok: 2.50, outputPerMTok: 10)
                )
            case .gpt4_1:
                return ModelProfile(
                    summary: "コーディング特化。コスト効率が良い",
                    modelFamily: "GPT",
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 2, outputPerMTok: 8)
                )
            case .o3:
                return ModelProfile(
                    summary: "高度な推論特化。複雑な問題解決に最適",
                    modelFamily: "o-series",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 2, outputPerMTok: 8)
                )
            case .o4Mini:
                return ModelProfile(
                    summary: "軽量推論。高速かつ低コスト",
                    modelFamily: "o-series",
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 1.10, outputPerMTok: 4.40)
                )
            }
        }
    }
}
