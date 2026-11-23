import Foundation

public struct CallDetector: Sendable {
    public enum Event: Sendable, Equatable {
        case started(String)
        case ended(String)
    }

    public static let settle: TimeInterval = 5
    public static let quiet: TimeInterval = 15
    public static let ignored: Set<String> = [
        "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX", "com.apple.PhotoBooth", "com.apple.garageband10",
        "com.apple.logic10",
    ]

    private var since: [String: Date] = [:]
    private var lastHeard: [String: Date] = [:]
    private var live: Set<String> = []

    public init() {}

    public var calls: Set<String> { live }

    public mutating func update(listening: Set<String>, at now: Date) -> [Event] {
        var events: [Event] = []
        for app in listening.subtracting(Self.ignored).sorted() {
            lastHeard[app] = now
            let start = since[app] ?? now
            since[app] = start
            if !live.contains(app), now.timeIntervalSince(start) >= Self.settle {
                live.insert(app)
                events.append(.started(app))
            }
        }
        for (app, heard) in lastHeard.sorted(by: { $0.key < $1.key })
        where !listening.contains(app) && now.timeIntervalSince(heard) >= Self.quiet {
            lastHeard[app] = nil
            since[app] = nil
            if live.remove(app) != nil { events.append(.ended(app)) }
        }
        return events
    }
}
