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

    public static func service(of url: URL) -> String? {
        guard url.scheme?.hasPrefix("http") == true else { return nil }
        return SourceDescriptor.callTranscript.callServices.service(ofInvite: url)
    }
}
