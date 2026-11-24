import Foundation

public enum MeetingLink {
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

    /// Whether `address`, as a browser shows it, is the link `url` joins: the same host and the same path, whatever the
    /// scheme, the query or a closing slash.
    public static func joins(_ url: URL, address: String) -> Bool {
        guard let other = URL(string: address.contains("://") ? address : "https://" + address) else { return false }
        func place(_ url: URL) -> String { (url.host()?.lowercased() ?? "") + url.path().replacing(#/\/+$/#, with: "") }
        return !place(url).isEmpty && place(url) == place(other)
    }

    public static func service(of url: URL) -> String? {
        guard url.scheme?.hasPrefix("http") == true else { return nil }
        return SourceDescriptor.callTranscript.callServices.service(ofInvite: url)
    }
}
