import Foundation

public struct TimedText: Sendable, Equatable {
    public var start: TimeInterval
    public var text: String

    public init(start: TimeInterval, text: String) {
        self.start = start
        self.text = text
    }
}

public struct CallLine: Codable, Sendable, Equatable {
    public enum Speaker: String, Codable, Sendable { case me, them }

    public var speaker: Speaker
    public var start: TimeInterval
    public var text: String

    public init(speaker: Speaker, start: TimeInterval, text: String) {
        self.speaker = speaker
        self.start = start
        self.text = text
    }
}

public enum CallTranscript {
    public static func merge(me: [TimedText], them: [TimedText]) -> [CallLine] {
        func lines(_ texts: [TimedText], _ speaker: CallLine.Speaker) -> [CallLine] {
            texts.map {
                CallLine(speaker: speaker, start: $0.start, text: $0.text.trimmingCharacters(in: .whitespaces))
            }
        }
        let spoken = (lines(me, .me) + lines(them, .them)).filter { !$0.text.isEmpty }.sorted(by: Self.earlier)
        var lines: [CallLine] = []
        for line in spoken {
            if let last = lines.last, last.speaker == line.speaker {
                lines[lines.count - 1].text += " " + line.text
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    private static func earlier(_ one: CallLine, _ other: CallLine) -> Bool {
        if one.start != other.start { return one.start < other.start }
        return one.speaker == .me && other.speaker == .them
    }

    public static func text(_ lines: [CallLine], me: String, them: String) -> String {
        lines.map { "[\(clock($0.start))] \($0.speaker == .me ? me : them): \($0.text)" }.joined(separator: "\n")
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }
}

public struct CallSummary: Codable, Sendable, Equatable {
    public struct Action: Codable, Sendable, Equatable {
        public var owner: String
        public var text: String

        public init(owner: String, text: String) {
            self.owner = owner
            self.text = text
        }
    }

    public var summary: String
    public var decisions: [String]
    public var actions: [Action]

    public init(summary: String, decisions: [String], actions: [Action]) {
        self.summary = summary
        self.decisions = decisions
        self.actions = actions
    }

    public static let schema = JSONSchema.object([
        .init("summary", .string), .init("decisions", .array(.string)),
        .init("actions", .array(.object([.init("owner", .string), .init("text", .string)]))),
    ])
}
