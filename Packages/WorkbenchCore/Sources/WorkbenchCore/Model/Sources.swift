/// A kind of personal data Workbench reads. Every read needs a grant of its kind from the capture policy.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case screen
    case screenText = "screen_text"
    case files
    /// What the person typed themselves, such as the action a deal waits for. It is not captured content: no switch,
    /// no grant, no run, and a delete of a source never removes it. See `Store.delete`.
    case typed
    case whatsapp
    case call
    /// Gmail threads opened inside one named label, read by the browser extension.
    case mail
    /// Today's events in the calendars the person chose, read through EventKit. Nothing is stored.
    case calendar
}

extension SourceKind {
    /// The kinds a capture switch and a grant stand for: every kind but what the person typed.
    public static var captured: [SourceKind] { allCases.filter { $0 != .typed } }
}
