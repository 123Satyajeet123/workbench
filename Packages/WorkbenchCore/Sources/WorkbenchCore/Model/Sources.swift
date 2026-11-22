public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case screen
    case screenText = "screen_text"
    case files
    case typed
    case whatsapp
    case call
    case mail
    case calendar
    case web
}

extension SourceKind {
    public static var captured: [SourceKind] { allCases.filter { $0 != .typed } }
}
