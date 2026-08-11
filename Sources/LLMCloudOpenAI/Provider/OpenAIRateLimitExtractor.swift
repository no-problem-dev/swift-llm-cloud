// OpenAIRateLimitExtractor is now available as OpenAICompatibleRateLimitExtractor
// from LLMCloudOpenAICompatible.
// This file provides a backward-compatible type alias.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient
import LLMCloudOpenAICompatible

/// Reads OpenAI's rate-limit headers: `retry-after` plus the `x-ratelimit-*` family, whose reset
/// values carry a duration suffix such as `6m` or `500ms`.
///
/// The implementation now lives in the OpenAI-compatible module and is shared with every vendor
/// that copies OpenAI's header names; this alias keeps the old name working.
package typealias OpenAIRateLimitExtractor = OpenAICompatibleRateLimitExtractor
