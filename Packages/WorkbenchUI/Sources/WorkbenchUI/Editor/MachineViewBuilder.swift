import Foundation
import WorkbenchCore

/// What a machine's blocks show, worked out here so the editor only draws it: the facts a view holds with their counts,
/// the answer of each formula, and the words of each chip. `titleOf` is the machine's own line for a fact with no quote.
struct MachineViewBuilder {
    var facts: [Item]
    var titleOf: (Item) -> String
    /// What the machine's spec and the clock say about its facts.
    var lens: FactsLens
    /// The day's one line for a group of facts, by the group's scope ("person: Asha"); empty when none is kept.
    var summaries: [String: Summary] = [:]
    /// Why a picker cannot choose for this machine, in words for the person; nil when it can.
    var pickerNote: (PickerKind) -> String?
    /// The marks the machine offers for a fact now.
    var marks: (Item) -> [FactMark] = { _ in [] }

    static let erasedNote = "The message this came from was deleted"

    /// The view the person's choice makes, or nil when the gate does not allow it.
    func changed(_ view: FactsView, to form: FactsView.Form, groupBy field: String) -> FactsView? {
        let changed = view.changed(
            to: form, groupBy: field.isEmpty ? view.groupBy : field, countField: FirstForm.countField(of: lens.spec))
        return changed.flatMap { gate.allows($0) ? $0 : nil }
    }

    private var gate: PageGate { PageGate(catalog: PageCatalog(spec: lens.spec, items: facts)) }

    func view(of block: MachineBlock, erased: Bool) -> MachineView {
        guard !erased else { return .erased(note: Self.erasedNote) }
        switch block {
        case .heading(let words): return .heading(text: words)
        case .text(let cited): return .text(text: cited.text, cites: chips(cited.cites))
        case .facts(let view): return .facts(rendering(of: view))
        case .grid(let grid): return .grid(rendering(of: grid))
        case .picker(let kind): return .picker(rendering(of: kind))
        }
    }

    private func chips(_ cites: [PageCite]) -> [CiteChip] {
        cites.map { cite in
            switch cite {
            case .fact(let id):
                guard let item = facts.first(where: { $0.id == id }) else {
                    return CiteChip(ref: cite.reference, label: "A fact", opens: false)
                }
                return CiteChip(
                    ref: cite.reference, label: FactHeadline(item: item, title: titleOf(item)).plain, opens: true)
            case .note: return CiteChip(ref: cite.reference, label: "Your words", opens: false)
            case .request: return CiteChip(ref: cite.reference, label: "Your request", opens: false)
            }
        }
    }

    private func rendering(of view: FactsView) -> FactsRendering {
        let sections = view.sections(in: facts, lens: lens)
        let tallyColumns =
            view.countBy.map { field in Self.firstSeen(sections.flatMap { tally(of: $0.facts, by: field) }) }
            ?? []
        let needing = sections.reduce(0) { $0 + needs(in: $1.facts) }
        return FactsRendering(
            title: view.title, layout: view.layout.rawValue,
            countText: Self.countText(sections.reduce(0) { $0 + $1.facts.count }),
            needsText: needing == 0 ? "" : (needing == 1 ? "1 needs you" : "\(needing) need you"),
            limit: view.limit ?? 0, viewBar: viewBar(of: view), columns: view.shownColumns, tallyColumns: tallyColumns,
            sections: sections.map { section in
                let newest = lens.newest(of: section.facts)
                return FactsRendering.Section(
                    name: section.name, countText: Self.countText(section.facts.count), count: section.facts.count,
                    needs: needs(in: section.facts), summary: summary(of: section.name, in: view.groupBy),
                    tally: view.countBy.map { counted(section.facts, by: $0, in: tallyColumns) } ?? [],
                    latest: newest.map { headline(of: $0).words } ?? "",
                    latestDay: newest.map(\.day).map(Self.dayText) ?? "",
                    rows: section.facts.compactMap { row(of: $0, view: view) })
            })
    }

    private func viewBar(of view: FactsView) -> FactsRendering.ViewBar {
        let options = gate.options(for: view, of: lens.spec)
        return FactsRendering.ViewBar(
            form: view.form.rawValue, forms: options.forms.map(\.rawValue), groupBy: view.groupBy ?? "",
            groups: options.groups)
    }

    private func needs(in facts: [Item]) -> Int { facts.filter { !lens.needs(of: $0).isEmpty }.count }

    private func tally(of facts: [Item], by field: String) -> [String] { lens.tally(of: facts, by: field).map(\.value) }

    private func counted(_ facts: [Item], by field: String, in columns: [String]) -> [FactsRendering.Tally] {
        let counts = Dictionary(uniqueKeysWithValues: lens.tally(of: facts, by: field).map { ($0.value, $0.count) })
        return columns.map { FactsRendering.Tally(value: $0, count: counts[$0] ?? 0, tone: lens.tone(of: $0).rawValue) }
    }

    private static func firstSeen(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func summary(of group: String, in field: String?) -> FactsRendering.Summary? {
        guard let field, let line = summaries["\(field): \(group)"]?.short else { return nil }
        return FactsRendering.Summary(text: line.text, cites: chips(line.cites.map(PageCite.fact)))
    }

    private func headline(of item: Item) -> FactHeadline { FactHeadline(item: item, title: titleOf(item)) }

    private func row(of item: Item, view: FactsView) -> FactsRendering.Row? {
        guard let id = item.id else { return nil }
        let headline = headline(of: item)
        let subject = lens.spec.subjectField
        let shownFields = (lens.spec.badges + [lens.spec.lifecycle?.field].compactMap { $0 })
            .filter { $0 != view.groupBy && $0 != subject && $0 != lens.spec.title }
        return FactsRendering.Row(
            fact: id, subject: subject.flatMap { $0 == view.groupBy ? nil : item[$0] } ?? "",
            words: headline.isQuote ? "\u{201C}\(headline.words)\u{201D}" : headline.words,
            cells: view.shownColumns.map { column in
                let value = PageCatalog.value(of: column, in: item)
                return column == PageCatalog.quoteColumn ? "\u{201C}\(value)\u{201D}" : value
            },
            needs: lens.needs(of: item).compactMap(tag(of:)),
            tags: Self.firstSeen(shownFields).compactMap { field in
                let value = item[field]
                return value.isEmpty ? nil : FactsRendering.Tag(text: value, tone: lens.tone(of: value).rawValue)
            },
            due: item.dueDay.map { "Due \(Self.dayText($0))" } ?? "",
            state: item.closed.map { "Closed: \($0.outcome)" } ?? "", marks: marks(item))
    }

    /// The tag a need gives a row. Trouble has none: the value that is in trouble shows with its own tone.
    private func tag(of need: FactNeed) -> FactsRendering.Tag? {
        switch need {
        case .asks: FactsRendering.Tag(text: "Asks you", tone: HelperSpec.Tone.attention.rawValue)
        case .late(let days):
            FactsRendering.Tag(
                text: days == 0 ? "Late" : "Late \(days) \(days == 1 ? "day" : "days")",
                tone: HelperSpec.Tone.bad.rawValue)
        case .trouble: nil
        }
    }

    private static func dayText(_ day: WorkDay) -> String {
        day.start.formatted(.dateTime.locale(Locale(identifier: "en")).weekday(.abbreviated).day().month(.abbreviated))
    }

    private func rendering(of grid: WorkbenchCore.Grid) -> GridRendering {
        let values = grid.values
        return GridRendering(
            title: grid.title, columns: grid.columns,
            rows: grid.rows.indices.map { row in
                grid.columns.indices.map { cell(source: grid.rows[row][$0], value: values[row][$0]) }
            }, cites: chips(grid.cites))
    }

    private func cell(source: String, value: WorkbenchCore.Grid.Value) -> GridRendering.Cell {
        switch value {
        case .failed: GridRendering.Cell(text: "Cannot work this out", kind: "failed", source: source)
        case .number(let number) where source.hasPrefix("="):
            GridRendering.Cell(
                text: number.formatted(.number.precision(.fractionLength(0...2))), kind: "formula", source: source)
        case .number: GridRendering.Cell(text: source, kind: "number", source: source)
        case .words: GridRendering.Cell(text: source, kind: "words", source: source)
        }
    }

    private func rendering(of kind: PickerKind) -> PickerRendering {
        let note = pickerNote(kind)
        return PickerRendering(
            source: kind.rawValue, title: PickerChoice.title(of: kind), note: note ?? "", available: note == nil)
    }

    static func countText(_ number: Int) -> String {
        switch number {
        case 0: "No facts yet"
        case 1: "1 fact"
        default: "\(number) facts"
        }
    }
}
