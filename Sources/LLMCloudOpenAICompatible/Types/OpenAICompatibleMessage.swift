import Foundation

/// OpenAI 互換メッセージ
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

    /// テキストのみのメッセージを作成
    package init(role: String, content: String?, toolCallId: String?, toolCalls: [OpenAICompatibleMessageToolCall]?) {
        self.role = role
        self.content = content.map { .text($0) }
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    /// マルチパートコンテンツのメッセージを作成
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

/// OpenAI 互換メッセージコンテンツ（テキストまたはマルチパート）
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

/// OpenAI 互換メッセージ内のツール呼び出し
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

/// OpenAI 互換メッセージ内のツール呼び出し関数
package struct OpenAICompatibleMessageToolCallFunction: Encodable, Sendable {
    package let name: String
    package let arguments: String

    package init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}
