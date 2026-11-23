import Foundation

/// What was said in each voice note file, by file; a file that was not heard is left out.
public typealias VoiceHearing = @Sendable ([URL]) async -> [URL: String]

/// Voice notes heard on this Mac. A chat reader writes a note's words as one line that starts with `tag`.
public enum VoiceText {
    public static let maximumCharacters = 4000
    public static let tag = "[voice note]"

    /// The words of a voice note as its line shows them, before its caption. Nil when nothing was heard.
    public static func line(heard: String?) -> String? {
        guard let heard, !heard.isEmpty else { return nil }
        return "\(tag) \(heard)"
    }

    public static func texts(in urls: [URL]) async -> [URL: String] { await shared.texts(in: urls) }

    private static let shared = Memo { url in
        guard #available(macOS 26, *) else { return nil }
        return try? await AppleTranscriber.english().transcribe(url)
    }

    actor Memo {
        struct Key: Hashable {
            let path: String
            let size: Int
            let modified: Date
        }

        private var texts: [Key: String] = [:]
        private var order: [Key] = []
        private let capacity: Int
        private let hear: @Sendable (URL) async -> String?

        init(capacity: Int = 500, hear: @escaping @Sendable (URL) async -> String?) {
            self.capacity = capacity
            self.hear = hear
        }

        func texts(in urls: [URL]) async -> [URL: String] {
            var found: [URL: String] = [:]
            for url in Set(urls) {
                if let text = await text(in: url) { found[url] = text }
            }
            return found
        }

        func text(in url: URL) async -> String? {
            guard let key = Self.key(for: url) else { return nil }
            if let known = texts[key] { return known }
            guard let heard = await hear(url) else { return nil }
            let text = String(heard.prefix(VoiceText.maximumCharacters))
            if texts.updateValue(text, forKey: key) == nil {
                order.append(key)
                if order.count > capacity { texts[order.removeFirst()] = nil }
            }
            return text
        }

        private static func key(for url: URL) -> Key? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date
            else { return nil }
            return Key(path: url.path, size: size, modified: modified)
        }
    }
}
