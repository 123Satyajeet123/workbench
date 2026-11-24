import Foundation

/// Where calls happen: the web sites and the apps, each with the service it names. A lookup on an address or a
/// bundle id, never on the words of a window.
public struct CallServices: Sendable, Equatable {
    var sites: [CallSite]
    var apps: [String: String]

    /// The service of a call tab at `address`: a site whose host and call path the address has.
    func service(atAddress address: String) -> String? {
        guard let url = URL(string: address.contains("://") ? address : "https://" + address) else { return nil }
        return sites.first { $0.hosts(url) && url.path().hasPrefix($0.callPath) }?.service
    }

    /// The service of a link that joins a meeting.
    func service(ofInvite url: URL) -> String? { sites.first { $0.invites(url) }?.service }

    static let known = CallServices(
        sites: [
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
        ],
        apps: [
            "us.zoom.xos": "Zoom", "com.microsoft.teams2": "Microsoft Teams", "com.microsoft.teams": "Microsoft Teams",
            "com.apple.FaceTime": "FaceTime", "net.whatsapp.WhatsApp": "WhatsApp",
            "com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord", "ru.keepcoder.Telegram": "Telegram",
            "org.telegram.desktop": "Telegram", "com.skype.skype": "Skype", "com.cisco.webexmeetingsapp": "Webex",
        ])
}

/// A web site where calls happen: its host, its service, where a call in a browser tab is (`callPath`), and the paths
/// of a link that joins a meeting (`invitePaths`; empty when the site gives none).
struct CallSite: Sendable, Equatable {
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
