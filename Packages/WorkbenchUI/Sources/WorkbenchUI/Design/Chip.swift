import SwiftUI

/// A short status word in a capsule. The fill carries the tone; the text stays in the body colour so it reads 7:1.
struct Chip: View {
    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .textStyle(.subheadline, weight: .medium)
            .foregroundStyle(.bodyText)
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs / 2)
            .background(tone.color.opacity(Self.fillOpacity), in: .capsule)
    }

    static let fillOpacity = 0.18
}
