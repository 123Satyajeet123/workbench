import SwiftUI
import WorkbenchCore

struct ItemRow: View {
    let model: HelperModel
    let item: Item
    let showsSpan: Bool
    /// A field the section already names, so its badge would repeat it.
    var grouping: String?

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if showsSpan {
                Text(span).textStyle(.callout, digits: true).foregroundStyle(.supporting)
                    .frame(width: 110, alignment: .leading)
            } else if let (value, tone) = toned {
                Image(systemName: tone.symbol).foregroundStyle(tone.color).frame(width: 18).accessibilityLabel(value)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(item[model.spec.title])
                    ForEach(badgeFields, id: \.self) { field in
                        Text(item[field]).textStyle(.caption).padding(.horizontal, Space.s).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }
                Text(showsSpan ? "“\(item.quote)”" : "“\(item.quote)” · \(time(item.start))")
                    .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            }
            .opacity(item.state == .rejected ? 0.5 : 1)
            .strikethrough(item.state == .rejected)
            Spacer()
            MarkButtons(state: item.state) { model.mark(item, as: $0) }
            ItemActions(model: model, item: item)
        }
    }

    /// The badge fields that have a value here, leaving out the field the section already names.
    private var badgeFields: [String] {
        model.spec.badges.filter { $0 != grouping && !item[$0].isEmpty }
    }

    /// The value of the first field whose values carry a tone, and that tone.
    private var toned: (String, HelperSpec.Tone)? {
        for field in model.spec.fields {
            if let tone = model.spec.tones[item[field.name]] { return (item[field.name], tone) }
        }
        return nil
    }

    private var span: String { "\(time(item.start))–\(time(item.end))" }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
