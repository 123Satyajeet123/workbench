import Foundation

/// One entry of a feed, as parsed: no judgement, only what the feed says.
public struct FeedEntry: Sendable, Equatable {
    public var title: String
    public var url: URL
    public var published: Date
    /// The entry's text as plain text: the full content when the feed gives it, else the summary.
    public var text: String
}

/// Reads RSS 2.0 (`item`) and Atom (`entry`) into entries. An entry with no https address, no title or no date is
/// left out.
public enum FeedParser {
    public static func entries(in data: Data) throws -> [FeedEntry] {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { throw FeedError.unreadable }
        return collector.entries
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var entries: [FeedEntry] = []
        private var fields: [String: String]?
        private var buffer = ""

        func parser(
            _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String]
        ) {
            if element == "item" || element == "entry" { fields = [:] }
            if fields != nil, element == "link", let href = attributes["href"], fields?["link"] == nil {
                fields?["link"] = href
            }
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        func parser(_ parser: XMLParser, foundCDATA data: Data) { buffer += String(decoding: data, as: UTF8.self) }

        func parser(
            _ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?
        ) {
            let key = Self.field(qualifiedName ?? element)
            let isFull = key == "content"
            if fields != nil, !buffer.isEmpty, fields?[key] == nil || isFull { fields?[key] = buffer }
            buffer = ""
            guard element == "item" || element == "entry", let found = fields else { return }
            fields = nil
            if let entry = Self.entry(found) { entries.append(entry) }
        }

        /// The names the two formats use for one thing.
        private static func field(_ element: String) -> String {
            switch element {
            case "pubDate", "published", "updated", "dc:date": "date"
            case "content:encoded", "content": "content"
            case "description", "summary": "summary"
            default: element
            }
        }

        private static func entry(_ found: [String: String]) -> FeedEntry? {
            guard let title = found["title"].flatMap({ HTMLText.plain($0).cleaned }),
                let link = found["link"]?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: link),
                url.scheme == "https", let date = found["date"].flatMap(published)
            else { return nil }
            return FeedEntry(
                title: title, url: url, published: date,
                text: HTMLText.plain(found["content"] ?? found["summary"] ?? ""))
        }

        private static let layouts = [
            "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z",
        ]

        private static func published(_ text: String) -> Date? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            return layouts.lazy.compactMap { layout in
                let format = DateFormatter()
                format.locale = Locale(identifier: "en_US_POSIX")
                format.dateFormat = layout
                return format.date(from: text)
            }.first
        }
    }
}
