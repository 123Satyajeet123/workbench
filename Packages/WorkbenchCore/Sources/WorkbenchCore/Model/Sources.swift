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
    /// The connections file of the person's own LinkedIn data export, chosen by hand. Like `dropped`, the act is the
    /// consent: no switch, no grant. Workbench never reads LinkedIn itself.
    case linkedinExport = "linkedin_export"
    /// What the person wrote in a project note. It is their own writing: the capture switch and pause do not stop it,
    /// and age does not erase it. Only the person's delete does. See `Store.saveNote`.
    case note
    case whatsapp
    case telegram
    case call
    case mail
    /// Today's events in the calendars the person chose, read through EventKit. Nothing is stored.
    case calendar
    /// Web research about a deal: the search queries Workbench sends to the search provider the founder chose, and the
    /// pages it fetches back. Off until the founder switches it on. See `WebGate`.
    case web
}

extension SourceKind {
    /// What the person gives by hand: the act of giving it is the consent.
    public static let byHand: Set<SourceKind> = [.typed, .dropped, .linkedinExport]

    public var isByHand: Bool { Self.byHand.contains(self) }

    /// The kinds a capture switch and a grant stand for: every kind but what the person gave by hand.
    public static var captured: [SourceKind] { allCases.filter { !$0.isByHand } }
}

extension SourceKind {
    /// The source as a person names it: the name of the first source that reads under this kind.
    public var words: String { SourceRegistry.descriptor(consent: self)?.name ?? rawValue }

    /// Where a fact came from, as "Captured from ...".
    public var capturedFrom: String { SourceRegistry.descriptor(consent: self)?.origin ?? rawValue }
}
