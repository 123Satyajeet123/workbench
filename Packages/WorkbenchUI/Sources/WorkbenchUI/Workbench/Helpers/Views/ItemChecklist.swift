import SwiftUI
import WorkbenchCore

struct ItemChecklist: View {
    let model: HelperModel
    let field: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Still open · \(model.open.count)").textStyle(.title3)
            if model.open.isEmpty {
                Text("Nothing open. Read a day to find \(model.spec.itemsNoun).").foregroundStyle(.supporting)
            }
            let openByValue = Dictionary(grouping: model.open) { $0[field] }
            ForEach(sections, id: \.self) { value in
                let own = openByValue[value, default: []]
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("\(value.isEmpty ? "Other" : value) · \(own.count)").textStyle(.headline)
                    ForEach(own) { item in
                        HStack(alignment: .top) {
                            ItemRow(model: model, item: item, showsSpan: false, grouping: field)
                            CloseMenu(outcomes: model.spec.lifecycle?.outcomes ?? []) { model.close(item, as: $0) }
                        }
                    }
                }
            }
            if !model.closed.isEmpty {
                Divider()
                Text("Closed on this day · \(model.closed.count)").textStyle(.title3)
                ForEach(model.closed) { ClosedRow(model: model, item: $0) }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.open.map(\.id))
    }

    private var sections: [String] {
        Dictionary(model.open.map { ($0[field], 1) }, uniquingKeysWith: +)
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}

struct CloseMenu: View {
    let outcomes: [String]
    let close: (String) -> Void

    var body: some View {
        Menu("Close") { ForEach(outcomes, id: \.self) { outcome in Button(outcome.capitalized) { close(outcome) } } }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Close it by hand when no message says so.")
    }
}

struct ClosedRow: View {
    let model: HelperModel
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.good.color).frame(width: 18)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(item[model.spec.title]).strikethrough()
                    if let outcome = item.closed?.outcome {
                        Text(outcome).pill()
                    }
                }
                Text(closing).textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            }
            Spacer()
            Button("Reopen") { model.reopen(item) }.help("A message did not really close it.")
        }
    }

    private var closing: String {
        guard let closed = item.closed else { return "" }
        let time = closed.at.formatted(date: .omitted, time: .shortened)
        guard let quote = closed.quote else { return "Closed by you · \(time)" }
        return "“\(quote)” · \(time) · opened \(item.day)"
    }
}
