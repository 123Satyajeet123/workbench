import Foundation

public struct CallSource: Equatable, Sendable {
    public var service: String
    public var title: String

    public init(service: String, title: String = "") {
        self.service = service
        self.title = title
    }

    public var label: String { title.isEmpty ? service : "\(service) · \(title)" }

    static let inPerson = CallSource(service: "In person")

    private static let sites: [(host: String, path: String, service: String)] = [
        ("meet.google.com", "", "Google Meet"), ("zoom.us", "", "Zoom"), ("teams.microsoft.com", "", "Microsoft Teams"),
        ("teams.live.com", "", "Microsoft Teams"), ("app.slack.com", "/huddle", "Slack"),
        ("discord.com", "", "Discord"),
        ("web.whatsapp.com", "", "WhatsApp"), ("whereby.com", "", "Whereby"), ("web.telegram.org", "", "Telegram"),
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
        let service = site(of: address) ?? apps[bundleID] ?? app
        let skipped = noise.union([app.lowercased(), service.lowercased()])
        return CallSource(service: service, title: cleanTitle(windowTitle, skipping: skipped))
    }

    private static func site(of address: String) -> String? {
        let url = URL(string: address.contains("://") ? address : "https://" + address)
        guard let host = url?.host()?.lowercased() else { return nil }
        let path = url?.path() ?? ""
        return sites.first { (host == $0.host || host.hasSuffix("." + $0.host)) && path.hasPrefix($0.path) }?.service
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
