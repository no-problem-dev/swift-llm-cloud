import Foundation
import LLMClient

// MARK: - Gemini Models

/// Google Gemini モデル
public enum GeminiModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)
    case pro31
    case pro3
    case flash3
    case pro25
    case flash25
    case flash25Lite

    // MARK: - Preview/Experimental Versions
    case pro31_preview(version: String)
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
        case .pro31:
            return "gemini-3.1-pro-preview"
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
        case .pro31_preview(let version):
            return "gemini-3.1-pro-preview-\(version)"
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
        case "gemini-3.1-pro-preview": self = .pro31
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
        case pro31 = "pro31"
        case flash3 = "flash3"
        case pro25 = "pro25"
        case flash25 = "flash25"

        public var id: String { rawValue }

        public var model: GeminiModel {
            switch self {
            case .pro31: return .pro31
            case .flash3: return .flash3
            case .pro25: return .pro25
            case .flash25: return .flash25
            }
        }

        public var displayName: String {
            switch self {
            case .pro31: return "Gemini 3.1 Pro"
            case .flash3: return "Gemini 3 Flash"
            case .pro25: return "Gemini 2.5 Pro"
            case .flash25: return "Gemini 2.5 Flash"
            }
        }

        public var shortName: String {
            switch self {
            case .pro31: return "3.1 Pro"
            case .flash3: return "3 Flash"
            case .pro25: return "2.5 Pro"
            case .flash25: return "2.5 Flash"
            }
        }

        /// モデルプロファイル
        public var profile: ModelProfile {
            switch self {
            case .pro31:
                return ModelProfile(
                    summary: "最新 Pro。最高品質の推論",
                    modelFamily: "Gemini",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio]
                )
            case .flash3:
                return ModelProfile(
                    summary: "高速 Flash。コスト効率に優れる",
                    modelFamily: "Gemini",
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code]
                )
            case .pro25:
                return ModelProfile(
                    summary: "高品質 Pro。複雑なタスクに強い",
                    modelFamily: "Gemini",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text, .vision, .code, .audio]
                )
            case .flash25:
                return ModelProfile(
                    summary: "バランス型 Flash。速度と品質の両立",
                    modelFamily: "Gemini",
                    toolCallSupport: .excellent,
                    japaneseSupport: .good,
                    modalities: [.text, .vision, .code]
                )
            }
        }
    }
}
