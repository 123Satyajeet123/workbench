import SwiftUI

/// A page title that wraps only between words. A word wider than the line shrinks, down to 70%, and never breaks.
struct PageTitle: View {
    let title: String

    var body: some View {
        WordWrap {
            ForEach(Array(Self.words(of: title).enumerated()), id: \.offset) { _, word in
                Text(word).textStyle(.largeTitle, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    /// The words of a title, each but the last with the space after it, so the words keep their usual gaps.
    static func words(of title: String) -> [String] {
        let words = title.split(separator: " ").map(String.init)
        return words.enumerated().map { $0.offset < words.count - 1 ? $0.element + " " : $0.element }
    }
}

/// Lays its children out as words in lines: a child goes to the next line when it does not fit after the one before.
/// Asked for its own width, it is one line. A child wider than the line gets the line's width, which a text with a
/// minimum scale factor shrinks into.
private struct WordWrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lines(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, lines(subviews, width: bounds.width).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var point = CGPoint.zero
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let natural = subview.sizeThatFits(.unspecified)
            if point.x > 0, point.x + natural.width > width {
                point = CGPoint(x: 0, y: point.y + lineHeight)
                lineHeight = 0
            }
            let fitted =
                natural.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : natural
            frames.append(CGRect(origin: point, size: fitted))
            point.x += fitted.width
            lineHeight = max(lineHeight, fitted.height)
            widest = max(widest, point.x)
        }
        return (frames, CGSize(width: widest, height: point.y + lineHeight))
    }
}
