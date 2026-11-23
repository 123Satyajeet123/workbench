import CoreGraphics
import Foundation
import ImageIO

/// The text of a file the person gives, page by page, read on this Mac: a PDF by `DeckText`, an image by Vision.
public enum FileText {
    /// One entry per page that holds text, with its page number from 1. An image is one page. Empty for a file that is
    /// neither or holds no text.
    public static func pages(in file: Data) -> [(page: Int, text: String)] {
        let pdf = DeckText.pages(in: file)
        guard pdf.isEmpty, let source = CGImageSourceCreateWithData(file as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return pdf }
        let text = ImageText.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? [] : [(1, text)]
    }
}
