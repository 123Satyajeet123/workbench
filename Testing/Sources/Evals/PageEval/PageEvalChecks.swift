import Foundation

@testable import WorkbenchCore

/// The scripted checks. Each is a pure function of the proposal: kinds, fields, values, ids and counts. None reads
/// the meaning of free text.
enum PageEvalChecks {
    static func matches(
        _ view: FactsView, layout: FactsView.Layout? = nil, groupBy: String? = nil, filters: [String: [String]] = [:]
    ) -> Bool {
        (layout == nil || view.layout == layout) && (groupBy == nil || view.groupBy == groupBy)
            && filters.allSatisfy { (view.filters[$0.key] ?? []).sorted() == $0.value.sorted() }
    }

    static func showsFactsView(
        _ outcome: PageEvalOutcome, layout: FactsView.Layout? = nil, groupBy: String? = nil,
        filters: [String: [String]] = [:]
    ) -> Bool {
        outcome.factsViews.contains { matches($0, layout: layout, groupBy: groupBy, filters: filters) }
    }

    static func showsTable(of kind: String, withColumns columns: Set<String>, _ outcome: PageEvalOutcome) -> Bool {
        outcome.factsViews.contains {
            $0.layout == .table && $0.filters["kind"] == [kind] && columns.isSubset(of: Set($0.columns))
        }
    }

    static func hasNoTable(_ outcome: PageEvalOutcome) -> Bool { !outcome.factsViews.contains { $0.layout == .table } }

    static func hasNoMachineBlock(_ outcome: PageEvalOutcome) -> Bool { outcome.result.blocks.isEmpty }

    static func personBlocksUnchanged(_ outcome: PageEvalOutcome) -> Bool {
        outcome.personBlocks == outcome.startPersonBlocks
    }

    static func gridHasNumbers(_ numbers: Set<Double>, _ outcome: PageEvalOutcome) -> Bool {
        numbers.isSubset(of: Set(outcome.grids.flatMap(\.values).flatMap { $0 }.compactMap(\.number)))
    }

    static func gridFormulaCount(_ outcome: PageEvalOutcome) -> Int {
        outcome.grids.flatMap(\.rows).flatMap { $0 }.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("=") }
            .count
    }

    static func everyGridCitesRequest(_ outcome: PageEvalOutcome) -> Bool {
        !outcome.grids.isEmpty && outcome.grids.allSatisfy { $0.cites.contains(.request) }
    }

    static func addsNoFactsView(_ outcome: PageEvalOutcome) -> Bool {
        !outcome.changedBlocks.contains { if case .facts = $0 { true } else { false } }
    }

    static func keepsEveryStartBlock(_ outcome: PageEvalOutcome) -> Bool {
        Set(outcome.start.page.blocks.keys).isSubset(of: Set(outcome.result.blocks.keys))
    }

    /// Every new or changed text cites at least one fact of `allowed`, and nothing else.
    static func newTextsCiteOnly(facts allowed: Set<Int64>, _ outcome: PageEvalOutcome) -> Bool {
        let texts = outcome.changedTexts
        return !texts.isEmpty
            && texts.allSatisfy { text in
                !text.cites.isEmpty
                    && text.cites.allSatisfy { if case .fact(let id) = $0 { allowed.contains(id) } else { false } }
            }
    }

    /// Every new or changed text has a cite, and every cite names a fact of the fixture, a paragraph of the page or the
    /// request.
    static func newTextsHaveResolvingCites(_ outcome: PageEvalOutcome) -> Bool {
        let facts = Set(outcome.facts.compactMap(\.id))
        let paragraphs = Set(outcome.result.order)
        let texts = outcome.changedTexts
        return !texts.isEmpty
            && texts.allSatisfy { text in
                !text.cites.isEmpty
                    && text.cites.allSatisfy {
                        switch $0 {
                        case .fact(let id): facts.contains(id)
                        case .note(let block): paragraphs.contains(.note(block))
                        case .request: true
                        }
                    }
            }
    }

    static func hasNoCiteRefusal(_ outcome: PageEvalOutcome) -> Bool {
        !outcome.refusals.contains {
            switch $0 {
            case .noCite, .unknownCite: true
            default: false
            }
        }
    }

    static func addsPicker(_ kind: PickerKind, _ outcome: PageEvalOutcome) -> Bool {
        outcome.changedPickers.contains(kind)
    }

    /// The one allowed operation updates the block `id` into a facts view of this title and layout.
    static func isOneUpdate(
        of id: MachineBlockID, titled title: String, layout: FactsView.Layout, _ outcome: PageEvalOutcome
    ) -> Bool {
        let allowed = outcome.proposal.allowed
        guard allowed.count == 1, outcome.proposal.verdicts.count == 1, case .update(id, .facts(let view)) = allowed[0]
        else { return false }
        return view.title == title && view.layout == layout
    }

    static func hasNoRefusal(_ outcome: PageEvalOutcome) -> Bool { outcome.refusals.isEmpty }

    /// The block `id` of the starting page is not on the resulting page.
    static func removes(_ id: MachineBlockID?, _ outcome: PageEvalOutcome) -> Bool {
        id.map { outcome.result.blocks[$0] == nil } ?? false
    }

    /// The block `id` of the starting page is on the resulting page as it was.
    static func leavesUnchanged(_ id: MachineBlockID?, _ outcome: PageEvalOutcome) -> Bool {
        id.map { outcome.start.page.blocks[$0] != nil && outcome.result.blocks[$0] == outcome.start.page.blocks[$0] }
            ?? false
    }

    /// The allowed operations are `inserts` inserts, `updates` updates and `removes` removes.
    static func hasOperations(inserts: Int, updates: Int, removes: Int, _ outcome: PageEvalOutcome) -> Bool {
        let operations = outcome.proposal.allowed
        func count(_ test: (PageOperation) -> Bool) -> Int { operations.filter(test).count }
        return count { if case .insert = $0 { true } else { false } } == inserts
            && count { if case .update = $0 { true } else { false } } == updates
            && count { if case .remove = $0 { true } else { false } } == removes
    }

    /// The block `id` is updated, and stays a facts view of this title and layout.
    static func updates(
        _ id: MachineBlockID?, toTitle title: String, layout: FactsView.Layout, _ outcome: PageEvalOutcome
    ) -> Bool {
        outcome.proposal.allowed.contains {
            if case .update(let updated, .facts(let view)) = $0 {
                updated == id && view.title == title && view.layout == layout
            } else {
                false
            }
        }
    }

    /// The facts view at this place of the resulting page has this layout, grouping and filters.
    static func placed(
        atPlace index: Int, layout: FactsView.Layout, groupBy: String? = nil, filters: [String: [String]] = [:],
        _ outcome: PageEvalOutcome
    ) -> Bool {
        outcome.factsView(atPlace: index).map { matches($0, layout: layout, groupBy: groupBy, filters: filters) }
            ?? false
    }

    /// A vague request gets at least one and at most two new blocks, none of them uncited words, and no paragraph of
    /// the person changes. This tests restraint and structure, not whether the answer is good.
    static func staysRestrained(_ outcome: PageEvalOutcome) -> Bool {
        (1...2).contains(outcome.newBlocks.count) && personBlocksUnchanged(outcome) && hasNoCiteRefusal(outcome)
            && outcome.changedTexts.allSatisfy { !$0.cites.isEmpty }
    }

    /// The page is full. The machine asks for nothing and the page is as it was; or every insert is refused for the
    /// cap and nothing else changes; or the proposal removes a block and inserts one, with no refusal, and the page is
    /// no larger than it was.
    static func respectsBlockCap(_ outcome: PageEvalOutcome) -> Bool {
        let declined = outcome.proposal.verdicts.isEmpty && outcome.result.blocks == outcome.start.page.blocks
        let inserts = outcome.proposal.verdicts.filter { if case .insert? = $0.operation { true } else { false } }
        let refusedAtCap =
            !inserts.isEmpty
            && inserts.allSatisfy {
                if case .tooManyBlocks? = $0.refusal { true } else { false }
            } && outcome.result.blocks == outcome.start.page.blocks
        let madeRoom =
            hasNoRefusal(outcome) && outcome.proposal.allowed.contains { if case .remove = $0 { true } else { false } }
            && outcome.proposal.allowed.contains { if case .insert = $0 { true } else { false } }
            && outcome.result.blocks.count <= outcome.start.page.blocks.count
        return declined || refusedAtCap || madeRoom
    }

    /// The one allowed operation updates the block `id` into a board of the blockers by person.
    static func isOneUpdateToBlockersBoard(of id: MachineBlockID?, _ outcome: PageEvalOutcome) -> Bool {
        let allowed = outcome.proposal.allowed
        guard allowed.count == 1, outcome.proposal.verdicts.count == 1,
            case .update(let updated, .facts(let view)) = allowed[0]
        else { return false }
        return updated == id && matches(view, layout: .board, groupBy: "person", filters: ["kind": ["blocker"]])
    }

    /// The request asks for something the facts cannot show. A correct proposal adds no facts view and no grid, is not
    /// refused, and says why in its note.
    static func declinesToShow(_ outcome: PageEvalOutcome) -> Bool {
        addsNoFactsView(outcome) && !outcome.changedBlocks.contains { if case .grid = $0 { true } else { false } }
            && hasNoRefusal(outcome) && hasNote(outcome)
    }

    /// A view cannot filter by day, so a correct proposal is a note, cited words, or a table that shows the day of each
    /// fact. It is not refused, and it says what it did in its note.
    static func answersWithoutDayFilter(_ outcome: PageEvalOutcome) -> Bool {
        hasNoRefusal(outcome) && hasNote(outcome)
            && outcome.changedBlocks.allSatisfy {
                switch $0 {
                case .text: true
                case .facts(let view): view.layout == .table && view.columns.contains(PageCatalog.dayColumn)
                default: false
                }
            }
    }

    static func hasNoOperation(_ outcome: PageEvalOutcome) -> Bool { outcome.proposal.verdicts.isEmpty }

    static func hasNote(_ outcome: PageEvalOutcome) -> Bool { !outcome.proposal.note.isEmpty }
}

extension Grid.Value {
    var number: Double? { if case .number(let number) = self { number } else { nil } }
}
