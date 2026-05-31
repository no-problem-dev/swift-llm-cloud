import Foundation

/// ドメイン認識リトライの単一実装。
///
/// `operation` を `RetryPolicy` に従って再試行する。失敗は `LLMError` または
/// （レート制限情報を伴う）`RateLimitAwareError` として送出される前提で、後者からは
/// 抽出済みの `RateLimitInfo` を遅延計算に利用し、各リトライで `RetryEvent` を発火する。
///
/// 契約経由(api-client)の送信は `decodeError` がリッチなエラーとレート制限情報を
/// `RateLimitAwareError` に載せて送出するため、ここでは生 HTTP レスポンスから
/// ヘッダーを再抽出する必要がない。
public enum RetryRunner {
    public static func run<R>(
        policy: any RetryPolicy,
        eventHandler: RetryEventHandler?,
        operation: () async throws -> R
    ) async throws -> R {
        var lastRateLimitInfo: RateLimitInfo?
        let maxAttempts = policy.maxRetries + 1

        for attempt in 1...maxAttempts {
            let llmError: LLMError
            do {
                return try await operation()
            } catch let rateLimitError as RateLimitAwareError {
                lastRateLimitInfo = rateLimitError.rateLimitInfo
                llmError = rateLimitError.underlyingError
            } catch let error as LLMError {
                llmError = error
            }

            guard policy.shouldRetry(error: llmError, attempt: attempt), attempt < maxAttempts else {
                throw llmError
            }

            let delay = policy.delay(for: attempt, error: llmError, rateLimitInfo: lastRateLimitInfo)
            eventHandler?(RetryEvent(
                attempt: attempt, maxRetries: policy.maxRetries, error: llmError, delaySeconds: delay
            ))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        throw LLMError.unknown(NSError(domain: "RetryRunner", code: -1))
    }
}
