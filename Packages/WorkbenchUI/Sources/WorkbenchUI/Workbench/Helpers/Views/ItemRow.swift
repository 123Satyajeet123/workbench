import SwiftUI
import WorkbenchCore

struct ItemRow: View {
    let model: HelperModel
    let item: Item
    let showsSpan: Bool
    /// A field the section already names, so its badge would repeat it.
    var grouping: String?
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if showsSpan {
                Text(span).textStyle(.callout, digits: true).foregroundStyle(.supporting)
                    .zoomedWidth(110, alignment: .leading)
            } else if let mark = markSymbol {
                Image(systemName: mark.symbol).foregroundStyle(mark.color).zoomedWidth(18)
                    .accessibilityLabel(item.state == .confirmed ? "Marked right" : "Marked wrong")
            } else if let (value, tone) = toned {
                Image(systemName: tone.symbol).foregroundStyle(tone.color)
                    .font(tone == .neutral ? .system(size: 7 * scale) : nil)
                    .frame(height: 18 * scale).zoomedWidth(18).accessibilityLabel(value)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(item[model.spec.title])
                    ForEach(badgeFields, id: \.self) { field in
                        Text(badge(item[field])).pill()
                    }
                }
                Text(showsSpan ? item.quotedWords : "\(item.quotedWords) · \(time(item.start))")
                    .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                if let triage = model.spec.triage(of: item) { WhyDisclosure(triage: triage) }
                if let note = hiddenNote {
                    Label(note, systemImage: "eye.slash").textStyle(.caption).foregroundStyle(.supporting)
                }
            }
            .opacity(item.state == .rejected ? 0.5 : 1)
            .strikethrough(item.state == .rejected)
            Spacer()
            HStack(spacing: Space.s) {
                MarkButtons(state: item.state) { model.mark(item, as: $0) }
                ItemActions(model: model, item: item)
            }
        }
    }

    private var markSymbol: (symbol: String, color: Color)? {
        switch item.state {
        case .confirmed: ("checkmark.circle.fill", Tone.good.color)
        case .rejected: ("xmark.circle.fill", Tone.bad.color)
        case .proposed: nil
        }
    }

    /// Said on the machine's own page when the founder hid the item or snoozed it: Today and the lists leave it out.
    private var hiddenNote: String? {
        guard item.isHidden(at: .now) else { return nil }
        if case .snoozed(let until) = item.hiding {
            return "Snoozed until \(until.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        }
        return "Hidden from Today"
    }

    private var badgeFields: [String] {
        model.spec.badges.filter { $0 != grouping && !item[$0].isEmpty }
    }

    private var toned: (String, HelperSpec.Tone)? {
        for field in model.spec.fields {
            if let tone = model.spec.tones[item[field.name]] { return (item[field.name], tone) }
        }
        return nil
    }

    private func badge(_ value: String) -> String {
        WorkDay(value).map { $0.start.formatted(.dateTime.weekday(.abbreviated).day().month()) } ?? value
    }

    private var span: String { "\(time(item.start))–\(time(item.end))" }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
