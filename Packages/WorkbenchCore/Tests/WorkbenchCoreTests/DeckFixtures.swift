import CoreGraphics
import CoreText
import Foundation

@testable import WorkbenchCore

/// A page of a test deck: text in the PDF's text layer, or the same words drawn as a picture with no text layer.
enum DeckPage {
    case text(String)
    case picture(String)
}

private let pageBox = CGRect(x: 0, y: 0, width: 600, height: 120)

/// A PDF with one page per entry.
func makeDeck(_ pages: [DeckPage]) -> Data {
    let data = NSMutableData()
    var box = pageBox
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for page in pages {
        context.beginPDFPage(nil)
        switch page {
        case .text(let words): draw(words, in: context)
        case .picture(let words): context.draw(picture(of: words), in: pageBox)
        }
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

/// The words in large black type on white, as a bitmap.
func picture(of words: String) -> CGImage {
    let scale: CGFloat = 2
    let context = CGContext(
        data: nil, width: Int(pageBox.width * scale), height: Int(pageBox.height * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
    context.scaleBy(x: scale, y: scale)
    draw(words, in: context)
    return context.makeImage()!
}

private func draw(_ words: String, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 40, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    context.textPosition = CGPoint(x: 20, y: 40)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: attributes)), context)
}

/// The deck cut into chunks of `size` bytes, in order.
func chunks(of deck: Data, name: String, context: MailContext, size: Int) -> [DeckChunk] {
    let pieces = stride(from: 0, to: deck.count, by: size).map { deck[$0..<min($0 + size, deck.count)] }
    return pieces.enumerated().map { index, piece in
        DeckChunk(
            context: context, name: name, index: index, count: pieces.count, data: piece.base64EncodedString())
    }
}
