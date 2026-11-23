/// A kind of personal data Workbench reads. Every read needs a grant of its kind from the capture policy.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case screen
    case screenText = "screen_text"
    case files
    /// What the person typed themselves, such as the action a deal waits for. It is not captured content: no switch,
    /// no grant, no run, and a delete of a source never removes it. See `Store.delete`.
    case typed
    /// A file the person added to a deal by hand. Like `typed`, the act is the consent: no switch, no grant.
    case dropped
    case whatsapp
    case call
    /// Gmail threads opened inside one named label, read by the browser extension.
    case mail
    /// Today's events in the calendars the person chose, read through EventKit. Nothing is stored.
    case calendar
    /// Web research about a deal: the search queries Workbench sends to the search provider the founder chose, and the
    /// pages it fetches back. Off until the founder switches it on. See `WebGate`.
    case web
}

extension SourceKind {
    /// What the person gives by hand: the act of giving it is the consent.
    public static let byHand: Set<SourceKind> = [.typed, .dropped]

    public var isByHand: Bool { Self.byHand.contains(self) }

    /// The kinds a capture switch and a grant stand for: every kind but what the person gave by hand.
    public static var captured: [SourceKind] { allCases.filter { !$0.isByHand } }
}

extension SourceKind {
    /// The source as a person names it.
    public var words: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .mail: "Mail"
        case .call: "Call"
        case .calendar: "Calendar"
        case .screen: "Screen"
        case .screenText: "Web page you read"
        case .web: "Web"
        case .files: "Files"
        case .typed: "Typed by you"
        case .dropped: "A file you added"
        }
    }
}
