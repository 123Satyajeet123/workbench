import SwiftUI
import WorkbenchCore

struct ItemRow: View {
    let model: HelperModel
    let item: Item
    let showsSpan: Bool
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
                        Text(item[field]).pill()
                    }
                }
                Text(showsSpan ? "“\(item.quote)”" : "“\(item.quote)” · \(time(item.start))")
                    .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                if let triage = model.spec.triage(of: item) { WhyDisclosure(triage: triage) }
                if let note = hiddenNote {
                    Label(note, systemImage: "eye.slash").textStyle(.caption).foregroundStyle(.supporting)
                }
            }
            .opacity(item.state == .rejected ? 0.5 : 1)
            .strikethrough(item.state == .rejected)
            Spacer()
            MarkButtons(state: item.state) { model.mark(item, as: $0) }
            ItemActions(model: model, item: item)
        }
    }

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

    private var span: String { "\(time(item.start))–\(time(item.end))" }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
