import CoreGraphics
import Foundation
import ImageIO
import Vision

/// The text in an image, recognized on this Mac by Apple's Vision. Nothing leaves the Mac. Teams post screenshots of
/// builds, logs and devices as updates (measured on the founder's group: 20 of 20 photos in a day held text).
public enum ImageText {
    /// Recognized text past this length is cut: a screenshot of a long log says little more per line.
    public static let maximumCharacters = 2000

    /// Empty when the file is not an image or holds no text.
    public static func recognize(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: " ").prefix(maximumCharacters))
    }
}
