/// A kind of personal data Workbench reads. Every read needs a grant of its kind from the capture policy.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case screen
    case screenText = "screen_text"
    case files
    case whatsapp
    case call
    /// Gmail threads opened inside one named label, read by the browser extension.
    case mail
}
