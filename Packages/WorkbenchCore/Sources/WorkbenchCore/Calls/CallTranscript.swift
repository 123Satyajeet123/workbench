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

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }
}

/// The notes on one call as the model writes them. Each point is one sentence that cites the transcript lines it
/// rests on by their numbers in the run's input, and quotes words of one of them exactly.
public struct CallSummary: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var text: String
        public var cites: [Int64]
        public var quote: String

        public init(text: String, cites: [Int64], quote: String) {
            self.text = text
            self.cites = cites
            self.quote = quote
        }
    }

    public var points: [Point]

    public init(points: [Point]) { self.points = points }

    public static let schema = JSONSchema.object([
        .init(
            "points",
            .array(.object([.init("text", .string), .init("cites", .array(.integer)), .init("quote", .string)])))
    ])
}
