import Foundation
import LLMClient

// MARK: - Gemini Models

/// Google Gemini モデル
public enum GeminiModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)
    case flash35
    case pro31
    case flashLite31
    case pro3
    case flash3
    case pro25
    case flash25
    case flash25Lite

    // MARK: - Preview/Experimental Versions
    case flash35_preview(version: String)
    case pro31_preview(version: String)
    case flashLite31_preview(version: String)
    case pro3_preview(version: String)
    case flash3_preview(version: String)
    case pro25_preview(version: String)
    case flash25_preview(version: String)
    case flash25Lite_preview(version: String)

    // MARK: - Custom
    case custom(String)

    // MARK: - Model ID

    public var id: String {
        switch self {
        case .flash35:
            return "gemini-3.5-flash"
        case .pro31:
            return "gemini-3.1-pro-preview"
        case .flashLite31:
            return "gemini-3.1-flash-lite"
        case .pro3:
            return "gemini-3-pro-preview"
        case .flash3:
            return "gemini-3-flash-preview"
        case .pro25:
            return "gemini-2.5-pro"
        case .flash25:
            return "gemini-2.5-flash"
        case .flash25Lite:
            return "gemini-2.5-flash-lite"
        case .flash35_preview(let version):
            return "gemini-3.5-flash-preview-\(version)"
        case .pro31_preview(let version):
            return "gemini-3.1-pro-preview-\(version)"
        case .flashLite31_preview(let version):
            return "gemini-3.1-flash-lite-preview-\(version)"
        case .pro3_preview(let version):
            return "gemini-3-pro-preview-\(version)"
        case .flash3_preview(let version):
            return "gemini-3-flash-preview-\(version)"
        case .pro25_preview(let version):
            return "gemini-2.5-pro-preview-\(version)"
        case .flash25_preview(let version):
            return "gemini-2.5-flash-preview-\(version)"
        case .flash25Lite_preview(let version):
            return "gemini-2.5-flash-lite-preview-\(version)"
        case .custom(let id):
            return id
        }
    }
}

// MARK: - RawValue Compatibility

extension GeminiModel: RawRepresentable {
    public var rawValue: String { id }

    public init?(rawValue: String) {
        switch rawValue {
        case "gemini-3.5-flash": self = .flash35
        case "gemini-3.1-pro-preview": self = .pro31
        case "gemini-3.1-flash-lite": self = .flashLite31
        case "gemini-3-pro-preview": self = .pro3
        case "gemini-3-flash-preview": self = .flash3
        case "gemini-2.5-pro": self = .pro25
        case "gemini-2.5-flash": self = .flash25
        case "gemini-2.5-flash-lite": self = .flash25Lite
        default: self = .custom(rawValue)
        }
    }
}

// MARK: - Preset

extension GeminiModel {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case flash35 = "flash35"
        case pro31 = "pro31"
        case flashLite31 = "flashLite31"
        case flash3 = "flash3"
        case pro25 = "pro25"
        case flash25 = "flash25"

        public var id: String { rawValue }

        public var model: GeminiModel {
            switch self {
            case .flash35: return .flash35
            case .pro31: return .pro31
            case .flashLite31: return .flashLite31
            case .flash3: return .flash3
            case .pro25: return .pro25
            case .flash25: return .flash25
            }
        }

        public var displayName: String {
            switch self {
            case .flash35: return "Gemini 3.5 Flash"
            case .pro31: return "Gemini 3.1 Pro"
            case .flashLite31: return "Gemini 3.1 Flash-Lite"
            case .flash3: return "Gemini 3 Flash"
            case .pro25: return "Gemini 2.5 Pro"
            case .flash25: return "Gemini 2.5 Flash"
            }
        }

        public var shortName: String {
            switch self {
            case .flash35: return "3.5 Flash"
            case .pro31: return "3.1 Pro"
            case .flashLite31: return "3.1 Flash-Lite"
            case .flash3: return "3 Flash"
            case .pro25: return "2.5 Pro"
            case .flash25: return "2.5 Flash"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .flash35:
                return ModelProfile(
                    summary: "最新 Flash。エージェント・コーディングに最強",
                    modelFamily: "Gemini",
                    description: "Gemini 3.5 Flash は Google の最新 Flash モデルで、エージェントワークフローとコーディングタスクにおいてフロンティアレベルの知性を持続的に発揮します。高速・低コストながら長期的なマルチステップタスクやサブエージェント展開に最適化されています。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_536,
                    knowledgeCutoff: "2025-01",
                    strengths: ["フロンティアレベルの知性", "エージェント最適化", "高速レスポンス", "コーディング性能"],
                    bestFor: ["エージェント開発", "マルチステップワークフロー", "コーディング支援", "大量処理"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 1.50, outputPerMTok: 9)
                )
            case .pro31:
                return ModelProfile(
                    summary: "最新 Pro。最高品質の推論",
                    modelFamily: "Gemini",
                    description: "Gemini 3.1 Pro は Google の最新最高性能モデルです。100 万トークンのコンテキストウィンドウでテキスト・画像・音声・動画・PDF のマルチモーダル入力に対応。エージェントワークフローに最適化されたバリアントも利用可能です。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_536,
                    knowledgeCutoff: "2025-01",
                    strengths: ["超大容量コンテキスト", "マルチモーダル", "エージェント最適化", "高品質推論"],
                    bestFor: ["マルチモーダル分析", "エージェント開発", "大量ドキュメント処理"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio],
                    pricing: Pricing(inputPerMTok: 2, outputPerMTok: 12)
                )
            case .flashLite31:
                return ModelProfile(
                    summary: "最速・最低コスト。高速エージェント向け",
                    modelFamily: "Gemini",
                    description: "Gemini 3.1 Flash-Lite は Gemini 3 シリーズ最速・最低コストのモデルです。2.5 Flash 比で 2.5 倍高速な TTFA と 45% の出力速度向上を実現。大量エージェントタスクやデータ抽出に最適。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_536,
                    knowledgeCutoff: "2025-01",
                    strengths: ["最速レスポンス", "最低コスト", "高スループット", "エージェント最適化"],
                    bestFor: ["大量エージェントタスク", "データ抽出", "超低レイテンシ処理"],
                    toolCallSupport: .good,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 0.25, outputPerMTok: 1.50)
                )
            case .flash3:
                return ModelProfile(
                    summary: "高速 Flash。コスト効率に優れる",
                    modelFamily: "Gemini",
                    description: "Gemini 3 Flash は Pro レベルの知性を Flash の速度とコストで提供するモデルです。思考レベルの調整が可能で、推論の深さとコストをタスクに応じてコントロールできます。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_536,
                    knowledgeCutoff: "2025-01",
                    strengths: ["Pro レベルの知性", "調整可能な思考レベル", "マルチモーダル", "ストリーミング関数呼び出し"],
                    bestFor: ["高スループット処理", "コスト効率重視の推論", "リアルタイムアプリケーション"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 0.50, outputPerMTok: 3)
                )
            case .pro25:
                return ModelProfile(
                    summary: "高品質 Pro。複雑なタスクに強い",
                    modelFamily: "Gemini",
                    description: "Gemini 2.5 Pro は深い推論とコーディングに優れたモデルです。思考モードに対応し、100 万トークンのコンテキストで長大なドキュメント分析が可能。Google 検索グラウンディングとの連携も利用できます。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_535,
                    knowledgeCutoff: "2025-01",
                    strengths: ["深い推論", "コーディング", "思考モード対応", "検索グラウンディング"],
                    bestFor: ["複雑なコーディング", "長文ドキュメント分析", "検索連携タスク"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio],
                    pricing: Pricing(inputPerMTok: 1.25, outputPerMTok: 10)
                )
            case .flash25:
                return ModelProfile(
                    summary: "バランス型 Flash。速度と品質の両立",
                    modelFamily: "Gemini",
                    description: "Gemini 2.5 Flash は Gemini ファミリーで最高の価格性能比を実現するモデルです。Flash で初めて思考機能を搭載し、低レイテンシで推論タスクを処理できます。",
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_535,
                    knowledgeCutoff: "2025-01",
                    strengths: ["最高の価格性能比", "思考機能搭載", "低レイテンシ", "マルチモーダル"],
                    bestFor: ["大量バッチ処理", "コスト重視の推論タスク", "マルチモーダルコンテンツ処理"],
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code],
                    pricing: Pricing(inputPerMTok: 0.30, outputPerMTok: 2.50)
                )
            }
        }
    }
}
