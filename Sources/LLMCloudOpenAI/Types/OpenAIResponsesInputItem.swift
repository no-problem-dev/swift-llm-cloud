import Foundation

/// One element of the input array sent to the Responses API.
///
/// Where Chat Completions takes a list of messages, the Responses API takes a list of items in
/// which role-bearing messages and standalone items such as function calls and their outputs sit
/// side by side. This enum is that union.
package enum OpenAIResponsesInputItem: Encodable, Sendable {
    /// A message whose content is a single run of text.
    case message(role: String, content: String)

    /// A message whose content mixes text and media.
    ///
    /// The API accepts `content` as either a string or an array, and the array form is used only
    /// when an image is present. Text-only messages stay strings, which keeps the wire shape
    /// identical to what a client without image support would send.
    case multipartMessage(role: String, parts: [OpenAIResponsesContentPart])

    /// A function call the assistant made earlier in the conversation.
    ///
    /// - Parameters:
    ///   - callId: Id that ties this call to its result. It has to be the id the model issued.
    ///   - name: Tool name.
    ///   - arguments: Arguments as a JSON string. The Responses API sends and expects a string
    ///     here, not a nested object.
    case functionCall(callId: String, name: String, arguments: String)

    /// The result of running a tool, handed back to the model.
    ///
    /// - Parameters:
    ///   - callId: Must equal the `call_id` of the function call it answers, or OpenAI rejects
    ///     the request.
    ///   - output: Result as a string. A tool that produced JSON has it serialized into this
    ///     string rather than nested as an object.
    case functionCallOutput(callId: String, output: String)

    package func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let role, let content):
            var container = encoder.container(keyedBy: MessageKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case .multipartMessage(let role, let parts):
            var container = encoder.container(keyedBy: MessageKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(parts, forKey: .content)
        case .functionCall(let callId, let name, let arguments):
            var container = encoder.container(keyedBy: FunctionCallKeys.self)
            try container.encode("function_call", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionCallOutput(let callId, let output):
            var container = encoder.container(keyedBy: FunctionCallOutputKeys.self)
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(output, forKey: .output)
        }
    }

    private enum MessageKeys: String, CodingKey {
        case role
        case content
    }

    private enum FunctionCallKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case name
        case arguments
    }

    private enum FunctionCallOutputKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }
}

// MARK: - Content Part

/// One element of a message whose content is an array rather than a plain string.
///
/// Both image cases encode as `input_image` and differ only in how the image is located: by
/// value in `image_url`, or by reference to a file already uploaded to OpenAI.
package enum OpenAIResponsesContentPart: Encodable, Sendable {
    case inputText(String)
    /// Image given by value: either a data URI such as `data:image/png;base64,…` or an HTTP URL
    /// OpenAI can fetch.
    case inputImage(url: String)
    /// Image given by reference to an id returned by the OpenAI Files API.
    case inputImageFile(fileId: String)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let url):
            try container.encode("input_image", forKey: .type)
            try container.encode(url, forKey: .imageUrl)
        case .inputImageFile(let fileId):
            try container.encode("input_image", forKey: .type)
            try container.encode(fileId, forKey: .fileId)
        }
    }

    private enum Keys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
        case fileId = "file_id"
    }
}
