import Foundation

public struct CallSource: Equatable, Sendable {
    public var service: String
    public var title: String
    public var isCall: Bool

    public init(service: String, title: String = "", isCall: Bool = true) {
        self.service = service
        self.title = title
        self.isCall = isCall
    }

    public var label: String { title.isEmpty ? service : "\(service) · \(title)" }

    static let inPerson = CallSource(service: "In person")

    /// Each web site of calls: its host, its service, where a call in a browser tab is (`callPath`), and the paths of
    /// a link that joins a meeting (`invitePaths`; empty when the site gives none). The one table a call tab and a
    /// calendar link are both named by.
    static let sites: [CallSite] = [
        CallSite("meet.google.com", "Google Meet", invitePaths: [""]),
        CallSite("zoom.us", "Zoom", invitePaths: ["/j/", "/my/", "/w/", "/s/"]),
        CallSite("teams.microsoft.com", "Microsoft Teams", invitePaths: ["/l/meetup-join", "/meet/"]),
        CallSite("teams.live.com", "Microsoft Teams", invitePaths: ["/meet/"]),
        CallSite("app.slack.com", "Slack", callPath: "/huddle", invitePaths: ["/huddle"]),
        CallSite("webex.com", "Webex", invitePaths: [""]),
        CallSite("facetime.apple.com", "FaceTime", invitePaths: ["/join"]),
        CallSite("whereby.com", "Whereby", invitePaths: [""]),
        CallSite("meet.jit.si", "Jitsi", invitePaths: [""]),
        CallSite("discord.gg", "Discord", invitePaths: [""]),
        CallSite("discord.com", "Discord"),
        CallSite("web.whatsapp.com", "WhatsApp"),
        CallSite("web.telegram.org", "Telegram"),
    ]

    private static let apps: [String: String] = [
        "us.zoom.xos": "Zoom", "com.microsoft.teams2": "Microsoft Teams", "com.microsoft.teams": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime", "net.whatsapp.WhatsApp": "WhatsApp", "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord", "ru.keepcoder.Telegram": "Telegram", "org.telegram.desktop": "Telegram",
        "com.skype.skype": "Skype", "com.cisco.webexmeetingsapp": "Webex",
    ]

    private static let noise: Set<String> = [
        "meet", "google meet", "zoom", "zoom meeting", "zoom workplace", "microsoft teams", "teams", "facetime",
        "whatsapp", "slack", "huddle", "discord", "telegram", "skype", "webex", "google chrome", "chrome", "safari",
        "arc", "brave", "microsoft edge", "firefox", "mozilla firefox", "meeting", "call",
        "camera and microphone recording", "microphone recording", "camera recording", "audio playing",
    ]

    public static func identify(app: String, bundleID: String, windowTitle: String, address: String) -> CallSource {
        if bundleID == "in-person" { return inPerson }
        let known = site(of: address) ?? apps[bundleID]
        let service = known ?? app
        let skipped = noise.union([app.lowercased(), service.lowercased()])
        return CallSource(service: service, title: cleanTitle(windowTitle, skipping: skipped), isCall: known != nil)
    }

    private static func site(of address: String) -> String? {
        guard let url = URL(string: address.contains("://") ? address : "https://" + address) else { return nil }
        return sites.first { $0.hosts(url) && url.path().hasPrefix($0.callPath) }?.service
    }

    private static func cleanTitle(_ title: String, skipping skipped: Set<String>) -> String {
        var parts = [title]
        for separator in [" - ", " – ", " — ", " | "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !skipped.contains($0.lowercased()) && !isMeetingCode($0) } ?? ""
    }

    private static func isMeetingCode(_ part: String) -> Bool {
        part.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil || part.wholeMatch(of: /[\d ]{9,13}/) != nil
    }
}

/// A web site where calls happen. See `CallSource.sites`.
struct CallSite: Sendable {
    let host: String
    let service: String
    let callPath: String
    let invitePaths: [String]

    init(_ host: String, _ service: String, callPath: String = "", invitePaths: [String] = []) {
        self.host = host
        self.service = service
        self.callPath = callPath
        self.invitePaths = invitePaths
    }

    func hosts(_ url: URL) -> Bool {
        guard let name = url.host()?.lowercased() else { return false }
        return name == host || name.hasSuffix("." + host)
    }

    /// A link that joins a meeting here. A site whose every path invites still needs a path past its root.
    func invites(_ url: URL) -> Bool {
        let path = url.path()
        return hosts(url) && invitePaths.contains { path.hasPrefix($0) } && !(invitePaths == [""] && path.count <= 1)
    }
}
