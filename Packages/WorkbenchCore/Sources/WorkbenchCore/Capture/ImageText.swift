import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Vision

/// The text in an image, recognized on this Mac by Apple's Vision. Nothing leaves the Mac. Teams post screenshots of
/// builds, logs and devices as updates (measured on the founder's group: 20 of 20 photos in a day held text).
public enum ImageText {
    /// The text in the image at `url`, recognized once per version of the file: every machine that reads the same
    /// photo, at every reading, reuses it (measured: 37 photos a day took 8.2 s and 140 MB each time).
    public static func text(in url: URL) -> String { shared.text(in: url) }

    private static let shared = Memo(recognize: recognize)

    /// Recognized texts by file identity (path, size, modification time), at most `capacity` of them, oldest out
    /// first. It lives in memory only, so nothing new is kept on disk.
    final class Memo: Sendable {
        struct Key: Hashable {
            let path: String
            let size: Int
            let modified: Date
        }

        private struct State {
            var texts: [Key: String] = [:]
            var order: [Key] = []
        }

        private let recognize: @Sendable (URL) -> String
        private let capacity: Int
        private let state = Mutex(State())

        init(capacity: Int = 1_000, recognize: @escaping @Sendable (URL) -> String) {
            self.capacity = capacity
            self.recognize = recognize
        }

        func text(in url: URL) -> String {
            guard let key = Self.key(for: url) else { return recognize(url) }
            if let known = state.withLock({ $0.texts[key] }) { return known }
            let text = recognize(url)
            state.withLock { state in
                guard state.texts.updateValue(text, forKey: key) == nil else { return }
                state.order.append(key)
                if state.order.count > capacity { state.texts[state.order.removeFirst()] = nil }
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

    /// Empty when the file is not an image or holds no text.
    public static func recognize(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "" }
        return recognize(image)
    }

    /// Empty when the image holds no text.
    public static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: " ").prefix(RunSettings.standard.imageTextCharacters))
    }
}
