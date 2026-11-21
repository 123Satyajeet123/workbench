import SwiftUI
import WorkbenchCore

/// One news signal as two lines: what happened and the words of the article it came from. Used on a deal card, in a
/// deal's detail and under a revisit on Today.
struct SignalLine: View {
    let signal: Item
    /// A card shows the line only; the detail also shows the quote.
    var showsQuote = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: tone.symbol).foregroundStyle(tone.color).accessibilityLabel(signal["polarity"])
            VStack(alignment: .leading, spacing: 2) {
                Text("\(signal["event"].capitalized) · \(signal[NewsSignals.headlineField])").textStyle(
                    .caption, weight: .medium
                )
                .lineLimit(showsQuote ? nil : 2)
                if showsQuote {
                    Text("“\(signal.quote)” · \(signal[NewsSignals.feedField]), \(signal["date"])")
                        .textStyle(.caption).foregroundStyle(.supporting).textSelection(.enabled)
                }
            }
        }
    }

    private var tone: HelperSpec.Tone { HelperSpec.newsSignals.tones[signal["polarity"]] ?? .neutral }
}
