import Foundation

public struct CallDetector: Sendable {
    public enum Event: Sendable, Equatable {
        case started(String)
        case ended(String)
    }

    /// When an app holding the microphone is a call. The defaults are home-made: no recorded calls have measured them.
    public struct Settings: Codable, Sendable, Equatable {
        /// Seconds an app must hold the microphone before its call starts.
        public var settle: TimeInterval = 5
        /// Seconds an app must stay silent before its call ends.
        public var quiet: TimeInterval = 15
        /// Bundle ids of apps that hold the microphone and never carry a call.
        public var ignored: Set<String> = [
            "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX", "com.apple.PhotoBooth", "com.apple.garageband10",
            "com.apple.logic10",
        ]

        public init() {}
    }

    private let settings: Settings
    private var since: [String: Date] = [:]
    private var lastHeard: [String: Date] = [:]
    private var live: Set<String> = []

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public var calls: Set<String> { live }

    public mutating func update(listening: Set<String>, at now: Date) -> [Event] {
        var events: [Event] = []
        for app in listening.subtracting(settings.ignored).sorted() {
            lastHeard[app] = now
            let start = since[app] ?? now
            since[app] = start
            if !live.contains(app), now.timeIntervalSince(start) >= settings.settle {
                live.insert(app)
                events.append(.started(app))
            }
        }
        for (app, heard) in lastHeard.sorted(by: { $0.key < $1.key })
        where !listening.contains(app) && now.timeIntervalSince(heard) >= settings.quiet {
            lastHeard[app] = nil
            since[app] = nil
            if live.remove(app) != nil { events.append(.ended(app)) }
        }
        return events
    }
}

extension Store {
    static let callDetectorKey = "calls.detector"

    public func saveCallDetectorSettings(_ settings: CallDetector.Settings) throws {
        try saveState(try Coding.json(settings), forKey: Self.callDetectorKey)
    }
}

extension Queries {
    /// The call detector's settings; the defaults for a store that has none.
    public func callDetectorSettings() throws -> CallDetector.Settings {
        try state(forKey: Store.callDetectorKey).map { try Coding.value(CallDetector.Settings.self, from: $0) }
            ?? CallDetector.Settings()
    }
}
