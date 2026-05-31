// OpenAIRateLimitExtractor is now available as OpenAICompatibleRateLimitExtractor
// from LLMCloudOpenAICompatible.
// This file provides a backward-compatible type alias.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMCloudClient
import LLMCloudOpenAICompatible

/// Backward-compatible type alias
package typealias OpenAIRateLimitExtractor = OpenAICompatibleRateLimitExtractor
