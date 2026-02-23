import Foundation

// MARK: - Gemini Models

/// Google Gemini モデル
public enum GeminiModel: Sendable, Equatable {
    // MARK: - Aliases (推奨)
    case flash3
    case pro25
    case flash25
    case flash25Lite
    case flash20
    case pro15
    case flash15

    // MARK: - Preview/Experimental Versions
    case flash3_preview(version: String)
    case pro25_preview(version: String)
    case flash25_preview(version: String)
    case flash25Lite_preview(version: String)

    // MARK: - Custom
    case custom(String)

    // MARK: - Model ID

    public var id: String {
        switch self {
        case .flash3:
            return "gemini-3-flash-preview"
        case .pro25:
            return "gemini-2.5-pro"
        case .flash25:
            return "gemini-2.5-flash"
        case .flash25Lite:
            return "gemini-2.5-flash-lite"
        case .flash20:
            return "gemini-2.0-flash"
        case .pro15:
            return "gemini-1.5-pro"
        case .flash15:
            return "gemini-1.5-flash"
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
        case "gemini-3-flash-preview": self = .flash3
        case "gemini-2.5-pro": self = .pro25
        case "gemini-2.5-flash": self = .flash25
        case "gemini-2.5-flash-lite": self = .flash25Lite
        case "gemini-2.0-flash": self = .flash20
        case "gemini-1.5-pro": self = .pro15
        case "gemini-1.5-flash": self = .flash15
        default: self = .custom(rawValue)
        }
    }
}

// MARK: - Preset

extension GeminiModel {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case flash3 = "flash3"
        case pro25 = "pro25"
        case flash25 = "flash25"
        case flash25Lite = "flash25Lite"

        public var id: String { rawValue }

        public var model: GeminiModel {
            switch self {
            case .flash3: return .flash3
            case .pro25: return .pro25
            case .flash25: return .flash25
            case .flash25Lite: return .flash25Lite
            }
        }

        public var displayName: String {
            switch self {
            case .flash3: return "Gemini 3 Flash"
            case .pro25: return "Gemini 2.5 Pro"
            case .flash25: return "Gemini 2.5 Flash"
            case .flash25Lite: return "Gemini 2.5 Flash-Lite"
            }
        }

        public var shortName: String {
            switch self {
            case .flash3: return "3 Flash"
            case .pro25: return "2.5 Pro"
            case .flash25: return "2.5 Flash"
            case .flash25Lite: return "2.5 Flash-Lite"
            }
        }
    }
}
