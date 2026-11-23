import SwiftUI

/// The place where the proof of a fact is drawn: the chat lines around it, with the cited lines marked. While the lines
/// load it holds rows of one line each, so the place is already about the size it will be.
struct ProofLines: View {
    let content: ProofContent
    @Environment(\.uiScale) private var scale
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch content {
        case .loading(let rows): placeholders(rows)
        case .lines(let lines): rows(lines)
        case .quote(let words): quote(words)
        case .notice(let text): notice(text, symbol: "questionmark.circle", tone: .supporting)
        case .problem(let text): notice(text, symbol: "exclamationmark.triangle", tone: Tone.bad.color)
        }
    }

    private func rows(_ lines: [ProofEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text(line.text(scale: scale, quoteFill: Color.accentFill.opacity(ProofStyle.quoteOpacity(scheme))))
                    .textStyle(.callout)
                    .foregroundStyle(line.isCited ? Color.bodyText : .supporting)
                    .modifier(ProofRow(isCited: line.isCited, tint: ProofStyle.citedOpacity(scheme)))
            }
        }
        .textSelection(.enabled)
    }

    private func placeholders(_ rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                Text(Self.placeholderText).textStyle(.callout).lineLimit(1).modifier(ProofRow(isCited: false, tint: 0))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading the chat lines")
    }

    private func quote(_ words: String) -> some View {
        Text("“\(words)”").text(.quote)
            .padding(.leading, Space.s)
            .overlay(alignment: .leading) { Rectangle().fill(Color.accentFill).frame(width: ProofStyle.barWidth) }
            .textSelection(.enabled)
    }

    private func notice(_ text: String, symbol: String, tone: some ShapeStyle) -> some View {
        Label {
            Text(text).text(.meta).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone)
        }
        .calloutBox(fillsWidth: true)
        .textSelection(.enabled)
    }

    private static let placeholderText = "00:00  Name  " + String(repeating: "x", count: 40)
}

/// The room around one line of the proof, the same for every line, so a cited line moves nothing.
private struct ProofRow: ViewModifier {
    let isCited: Bool
    let tint: Double

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(isCited ? Color.accentFill.opacity(tint) : .clear)
            .overlay(alignment: .leading) {
                if isCited { Rectangle().fill(Color.accentFill).frame(width: ProofStyle.barWidth) }
            }
            .clipShape(.rect(cornerRadius: Radius.keyCap))
    }
}
