import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// プロバイダのレート制限ヘッダー名とリセット値形式を宣言する設定。
///
/// 各プロバイダは「ヘッダー名 + リセット形式」だけを供給し、抽出ロジックは1実装に集約する。
public struct RateLimitHeaderExtraction: Sendable {
    public enum ResetFormat: Sendable {
        /// RFC3339 絶対時刻 → 現在からの残り秒（負値は 0 にクランプ）。Anthropic。
        case rfc3339
        /// `1s`/`500ms`/`6m`/`1h` のような duration suffix。OpenAI 互換。
        case durationSuffix
        /// 残り秒の数値。
        case seconds
    }

    public var retryAfter: String?
    public var remainingRequests: String?
    public var requestsReset: String?
    public var remainingTokens: String?
    public var tokensReset: String?
    public var resetFormat: ResetFormat

    public init(
        retryAfter: String? = "retry-after",
        remainingRequests: String? = nil,
        requestsReset: String? = nil,
        remainingTokens: String? = nil,
        tokensReset: String? = nil,
        resetFormat: ResetFormat = .seconds
    ) {
        self.retryAfter = retryAfter
        self.remainingRequests = remainingRequests
        self.requestsReset = requestsReset
        self.remainingTokens = remainingTokens
        self.tokensReset = tokensReset
        self.resetFormat = resetFormat
    }

    public func extract(from response: HTTPURLResponse) -> RateLimitInfo {
        func value(_ name: String?) -> String? { name.flatMap { response.value(forHTTPHeaderField: $0) } }
        return build(value)
    }

    /// contract の `decodeError` が受け取る `[String: String]` ヘッダー辞書からの抽出
    /// （大文字小文字を無視）。`HTTPURLResponse` 版と同一ロジックを共有する。
    public func extract(from headers: [String: String]) -> RateLimitInfo {
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, b in b })
        func value(_ name: String?) -> String? { name.flatMap { lowered[$0.lowercased()] } }
        return build(value)
    }

    private func build(_ value: (String?) -> String?) -> RateLimitInfo {
        RateLimitInfo(
            retryAfter: value(retryAfter).flatMap { Double($0) },
            remainingRequests: value(remainingRequests).flatMap { Int($0) },
            requestsResetIn: value(requestsReset).flatMap(parseReset),
            remainingTokens: value(remainingTokens).flatMap { Int($0) },
            tokensResetIn: value(tokensReset).flatMap(parseReset)
        )
    }

    private func parseReset(_ raw: String) -> TimeInterval? {
        switch resetFormat {
        case .seconds:
            return Double(raw.trimmingCharacters(in: .whitespaces))
        case .rfc3339:
            return RateLimitHeaderExtraction.parseRFC3339(raw)
        case .durationSuffix:
            return RateLimitHeaderExtraction.parseDurationSuffix(raw)
        }
    }

    private static func parseRFC3339(_ value: String) -> TimeInterval? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    private static func parseDurationSuffix(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("ms") { return Double(trimmed.dropLast(2)).map { $0 / 1000 } }
        if trimmed.hasSuffix("s") { return Double(trimmed.dropLast(1)) }
        if trimmed.hasSuffix("m") { return Double(trimmed.dropLast(1)).map { $0 * 60 } }
        if trimmed.hasSuffix("h") { return Double(trimmed.dropLast(1)).map { $0 * 3600 } }
        return Double(trimmed)
    }

    /// Anthropic: `anthropic-ratelimit-*` + RFC3339 reset。
    public static let anthropic = RateLimitHeaderExtraction(
        retryAfter: "retry-after",
        remainingRequests: "anthropic-ratelimit-requests-remaining",
        requestsReset: "anthropic-ratelimit-requests-reset",
        remainingTokens: "anthropic-ratelimit-tokens-remaining",
        tokensReset: "anthropic-ratelimit-tokens-reset",
        resetFormat: .rfc3339
    )

    /// OpenAI 互換: `x-ratelimit-*` + duration suffix reset。
    public static let openAICompatible = RateLimitHeaderExtraction(
        retryAfter: "retry-after",
        remainingRequests: "x-ratelimit-remaining-requests",
        requestsReset: "x-ratelimit-reset-requests",
        remainingTokens: "x-ratelimit-remaining-tokens",
        tokensReset: "x-ratelimit-reset-tokens",
        resetFormat: .durationSuffix
    )

    /// Gemini: `retry-after` のみ。
    public static let gemini = RateLimitHeaderExtraction(retryAfter: "retry-after")
}
