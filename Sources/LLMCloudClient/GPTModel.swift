import Foundation

// MARK: - GPT Models

/// OpenAI GPT モデル
///
/// エイリアス（推奨）または固定バージョンでモデルを指定できます。
public enum GPTModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)

    /// GPT-4o 最新版（マルチモーダル）
    case gpt4o

    /// GPT-4o mini 最新版（軽量版）
    case gpt4oMini

    /// GPT-4 Turbo 最新版
    case gpt4Turbo

    /// GPT-4 最新版
    case gpt4

    /// o1 最新版（推論特化）
    case o1

    /// o3 最新版（高度な推論）
    case o3

    /// o3-mini 最新版（軽量推論）
    case o3Mini

    /// o4-mini 最新版（最新軽量推論）
    case o4Mini

    // MARK: - Fixed Versions

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
        // Aliases
        case .gpt4o:
            return "gpt-4o"
        case .gpt4oMini:
            return "gpt-4o-mini"
        case .gpt4Turbo:
            return "gpt-4-turbo"
        case .gpt4:
            return "gpt-4"
        case .o1:
            return "o1"
        case .o3:
            return "o3"
        case .o3Mini:
            return "o3-mini"
        case .o4Mini:
            return "o4-mini"
        // Fixed versions
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
        // Custom
        case .custom(let id):
            return id
        }
    }
}

// MARK: - Preset

extension GPTModel {
    /// UI選択用のプリセットモデル
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case gpt4o = "gpt4o"
        case gpt4oMini = "gpt4oMini"
        case o1 = "o1"
        case o3Mini = "o3Mini"

        public var id: String { rawValue }

        public var model: GPTModel {
            switch self {
            case .gpt4o: return .gpt4o
            case .gpt4oMini: return .gpt4oMini
            case .o1: return .o1
            case .o3Mini: return .o3Mini
            }
        }

        public var displayName: String {
            switch self {
            case .gpt4o: return "GPT-4o"
            case .gpt4oMini: return "GPT-4o mini"
            case .o1: return "o1"
            case .o3Mini: return "o3-mini"
            }
        }

        public var shortName: String {
            switch self {
            case .gpt4o: return "4o"
            case .gpt4oMini: return "4o mini"
            case .o1: return "o1"
            case .o3Mini: return "o3-mini"
            }
        }
    }
}
