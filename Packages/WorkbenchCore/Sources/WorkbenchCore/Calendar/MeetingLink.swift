import Foundation

public enum MeetingLink {
    private static let services: [(host: String, paths: [String], name: String)] = [
        ("meet.google.com", [""], "Google Meet"), ("zoom.us", ["/j/", "/my/", "/w/", "/s/"], "Zoom"),
        ("teams.microsoft.com", ["/l/meetup-join", "/meet/"], "Microsoft Teams"),
        ("teams.live.com", ["/meet/"], "Microsoft Teams"), ("webex.com", [""], "Webex"),
        ("facetime.apple.com", ["/join"], "FaceTime"), ("app.slack.com", ["/huddle"], "Slack"),
        ("whereby.com", [""], "Whereby"), ("meet.jit.si", [""], "Jitsi"), ("discord.gg", [""], "Discord"),
    ]

    public static func find(in texts: [String?], orAnyLinkIn fallback: [String?] = []) -> URL? {
        links(in: texts).first { service(of: $0) != nil }
            ?? links(in: fallback).first { $0.scheme == "https" || $0.scheme == "http" }
    }

    private static func links(in texts: [String?]) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return texts.compactMap(\.self).flatMap { text in
            (detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).compactMap(\.url)
        }
    }

    public static func service(of url: URL) -> String? {
        guard let host = url.host()?.lowercased(), url.scheme?.hasPrefix("http") == true else { return nil }
        let path = url.path()
        return services.first { service in
            (host == service.host || host.hasSuffix("." + service.host))
                && service.paths.contains { path.hasPrefix($0) } && !(service.paths == [""] && path.count <= 1)
        }?.name
    }
}
