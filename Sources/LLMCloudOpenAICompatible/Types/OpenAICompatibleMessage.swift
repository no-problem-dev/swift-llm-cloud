import Foundation

/// One conversation message in the shape Chat Completions accepts.
///
/// Encoding is written out by hand so that nil fields vanish from the payload instead of being sent
/// as null: `tool_call_id` belongs only on a tool message, `tool_calls` only on an assistant
/// message, and an assistant message that is nothing but tool calls carries no content at all.
package struct OpenAICompatibleMessage: Encodable, Sendable {
    package let role: String
    package let content: OpenAICompatibleMessageContent?
    package let toolCallId: String?
    package let toolCalls: [OpenAICompatibleMessageToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    /// Creates a message whose content is a single string, or none at all when it is nil.
    package init(role: String, content: String?, toolCallId: String?, toolCalls: [OpenAICompatibleMessageToolCall]?) {
        self.role = role
        self.content = content.map { .text($0) }
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    /// Creates a message whose content is an array of parts, for text mixed with images or audio.
    package init(role: String, contentParts: [OpenAICompatibleContentPart], toolCallId: String?, toolCalls: [OpenAICompatibleMessageToolCall]?) {
        self.role = role
        self.content = .parts(contentParts)
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        if let content = content {
            try container.encode(content, forKey: .content)
        }

        if let toolCallId = toolCallId {
            try container.encode(toolCallId, forKey: .toolCallId)
        }

        if let toolCalls = toolCalls {
            try container.encode(toolCalls, forKey: .toolCalls)
        }
    }
}

/// Message content, which the wire format lets be either a bare string or an array of parts.
///
/// It encodes as the value itself with no wrapper object, so the receiving vendor sees exactly the
/// two shapes it expects.
package enum OpenAICompatibleMessageContent: Encodable, Sendable {
    case text(String)
    case parts([OpenAICompatibleContentPart])

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

/// A tool call replayed back to the model as part of the conversation history.
///
/// The id has to be the one the vendor issued, because the tool result messages that follow refer
/// to it.
package struct OpenAICompatibleMessageToolCall: Encodable, Sendable {
    package let id: String
    package let type: String
    package let function: OpenAICompatibleMessageToolCallFunction

    package init(id: String, type: String, function: OpenAICompatibleMessageToolCallFunction) {
        self.id = id
        self.type = type
        self.function = function
    }
}

/// Name and arguments of a replayed tool call, with the arguments as a JSON string rather than an
/// object, matching how the vendor sent them.
package struct OpenAICompatibleMessageToolCallFunction: Encodable, Sendable {
    package let name: String
    package let arguments: String

    package init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}
