import Foundation

// MARK: - SSEEvent (Public)

public struct SSEParsedEvent: Sendable {
    public let event: String?
    public let data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

// MARK: - SSELineParser

public struct SSELineParser: Sendable {
    private var currentEvent: String?
    private var currentData: [String] = []

    public init() {}

    public mutating func parseLine(_ line: String) -> SSEParsedEvent? {
        if line.isEmpty {
            guard !currentData.isEmpty else { return nil }
            let event = SSEParsedEvent(
                event: currentEvent,
                data: currentData.joined(separator: "\n")
            )
            currentEvent = nil
            currentData = []
            return event
        }

        if line.hasPrefix(":") {
            return nil
        }

        if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }

        return nil
    }
}

// MARK: - DataLineBuffer

public struct DataLineBuffer: Sendable {
    private var buffer = ""

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        buffer += text

        var lines: [String] = []
        while let newlineRange = buffer.range(of: "\r\n") ?? buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            lines.append(line)
            buffer = String(buffer[newlineRange.upperBound...])
        }
        return lines
    }
}
