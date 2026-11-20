import CoreGraphics
import Foundation
import PDFKit

/// The text of a PDF deck, page by page, read on this Mac: the page's own text, else the text Vision recognizes in the
/// rendered page.
public enum DeckText {
    /// Pixels per point when a page is rendered for recognition (about 150 dpi).
    static let renderScale: CGFloat = 2

    /// One entry per page that holds text, with its page number from 1.
    public static func pages(in pdf: Data) -> [(page: Int, text: String)] {
        guard let document = PDFDocument(data: pdf) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let own = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = own.isEmpty ? recognized(page) : own
            return text.isEmpty ? nil : (index + 1, text)
        }
    }

    private static func recognized(_ page: PDFPage) -> String {
        guard let image = render(page) else { return "" }
        return ImageText.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let box = reference.getBoxRect(.mediaBox)
        let width = Int(box.width * renderScale)
        let height = Int(box.height * renderScale)
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: renderScale, y: renderScale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(reference)
        return context.makeImage()
    }
}
