import Foundation
import SwiftUI
import WorkbenchCore

/// One chat line as the inspector draws it: its time in the inspector's words, who said it, the words, and which words
/// are the quote.
struct ProofEntry: Identifiable, Equatable {
    let id: Int64
    let time: String?
    let sender: String?
    let words: String
    let isCited: Bool
    /// The quote inside `words`, in Unicode scalars of its normal form C. Nil when the quote is the whole line or when
    /// the line is not a WhatsApp message: only there are the words the text a quote span counts in.
    let quote: Range<Int>?

    static let longestSender = 60

    init(_ line: ChatLine, of item: Item, _ dates: DateWords) {
        id = line.id
        time = line.time.map(dates.time)
        isCited = line.isCited
        let parts = Self.parts(of: line.text, from: item.source)
        sender = parts.sender
        words = parts.words.nfc
        quote = line.isCited && item.source == .whatsapp ? Self.quote(of: item, in: words, line: line.id) : nil
    }

    static func lines(_ chat: [ChatLine], of item: Item, _ dates: DateWords) -> [ProofEntry] {
        chat.map { ProofEntry($0, of: item, dates) }
    }

    /// A WhatsApp line is `Sender: words`, or `[Chat] Sender: words` when a machine reads several chats.
    static func parts(of text: String, from source: SourceKind) -> (sender: String?, words: String) {
        guard source == .whatsapp, let colon = text.range(of: ": "),
            text.distance(from: text.startIndex, to: colon.lowerBound) <= longestSender
        else { return (nil, text) }
        let sender = String(text[..<colon.lowerBound])
        return (sender.droppingChatTag, String(text[colon.upperBound...]))
    }

    private static func quote(of item: Item, in words: String, line: Int64) -> Range<Int>? {
        guard let span = item.quoteSpan, span.line == line, span.part == 0 else { return nil }
        let length = words.unicodeScalars.count
        guard 0 <= span.start, span.start < span.end, span.end <= length, span.end - span.start < length else {
            return nil
        }
        return span.start..<span.end
    }

    /// The line as one run of text: time, sender in semibold, then the words with the quote marked.
    func text(scale: Double, quoteFill: Color) -> AttributedString {
        var result = AttributedString()
        if let time {
            var stamp = AttributedString(time + "  ")
            stamp.font = Font.system(size: Font.TextStyle.subheadline.macSize * scale).monospacedDigit()
            stamp.foregroundColor = .supporting
            result += stamp
        }
        if let sender {
            var name = AttributedString(sender + "  ")
            name.font = Font.system(size: Font.TextStyle.callout.macSize * scale, weight: .semibold)
            result += name
        }
        return result + marked(quoteFill)
    }

    private func marked(_ fill: Color) -> AttributedString {
        var text = AttributedString(words)
        guard let quote else { return text }
        let scalars = text.unicodeScalars
        let start = scalars.index(scalars.startIndex, offsetBy: quote.lowerBound)
        let end = scalars.index(scalars.startIndex, offsetBy: quote.upperBound)
        text[start..<end].backgroundColor = fill
        return text
    }
}

extension String {
    fileprivate var droppingChatTag: String {
        guard hasPrefix("["), let close = range(of: "] ") else { return self }
        return String(self[close.upperBound...])
    }
}

/// How the proof marks what the fact cites: a bar and a soft tint on the cited lines, a stronger tint on the quote.
enum ProofStyle {
    static let barWidth: CGFloat = 2

    /// The tint of a cited line. Dark surfaces need more of the accent to show the same.
    static func citedOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.16 : 0.09 }
    static func quoteOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.5 : 0.28 }
}
