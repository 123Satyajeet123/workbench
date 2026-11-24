import Foundation

@testable import WorkbenchCore

/// Tasks that can fail where the base tasks do not. Each check is written before the run and reads only the proposal.
extension PageEvalTask {
    static let multipleOperationsGroup = "several operations"
    static let vagueGroup = "vague request"
    static let blockCapGroup = "block cap"
    static let touchedGroup = "touched block"
    static let fundGroup = "fund"

    /// The id of the one block the standard page starts with.
    private static func seededBlock(_ outcome: PageEvalOutcome) -> MachineBlockID? {
        outcome.start.page.blocks.keys.first
    }

    static let multipleOperations: [PageEvalTask] = [
        PageEvalTask(
            "remove and add three",
            "Remove your table, add a board of plans by person, a list of blockers, and a count of facts by project.",
            group: multipleOperationsGroup
        ) { outcome in
            PageEvalChecks.removes(seededBlock(outcome), outcome) && PageEvalChecks.hasNoRefusal(outcome)
                && PageEvalChecks.personBlocksUnchanged(outcome)
                && PageEvalChecks.showsFactsView(
                    outcome, layout: .board, groupBy: "person", filters: ["kind": ["plan"]])
                && PageEvalChecks.showsFactsView(outcome, layout: .list, filters: ["kind": ["blocker"]])
                && PageEvalChecks.showsFactsView(outcome, layout: .counts, groupBy: "project")
        },
        PageEvalTask(
            "update and add two",
            "Rename your table to \"\(renamedTitle)\", then add a board of plans by person and a list of blockers.",
            group: multipleOperationsGroup
        ) { outcome in
            PageEvalChecks.hasOperations(inserts: 2, updates: 1, removes: 0, outcome)
                && PageEvalChecks.hasNoRefusal(outcome)
                && PageEvalChecks.updates(seededBlock(outcome), toTitle: renamedTitle, layout: .table, outcome)
                && PageEvalChecks.showsFactsView(
                    outcome, layout: .board, groupBy: "person", filters: ["kind": ["plan"]])
                && PageEvalChecks.showsFactsView(outcome, layout: .list, filters: ["kind": ["blocker"]])
        },
        PageEvalTask(
            "insert after my paragraph",
            "Add a list of blockers right after my offsite budget note, and a count of facts by project at the end.",
            group: multipleOperationsGroup
        ) { outcome in
            // The page starts as: job paragraph, budget paragraph, table.
            PageEvalChecks.hasNoRefusal(outcome) && PageEvalChecks.personBlocksUnchanged(outcome)
                && PageEvalChecks.leavesUnchanged(seededBlock(outcome), outcome)
                && PageEvalChecks.placed(atPlace: 2, layout: .list, filters: ["kind": ["blocker"]], outcome)
                && PageEvalChecks.placed(atPlace: 4, layout: .counts, groupBy: "project", outcome)
        },
    ]

    static let vague: [PageEvalTask] = [
        PageEvalTask("tidy", "Tidy this page.", group: vagueGroup, passes: PageEvalChecks.staysRestrained),
        PageEvalTask(
            "look first", "What should I look at first?", group: vagueGroup, passes: PageEvalChecks.staysRestrained),
        PageEvalTask(
            "monday meeting", "Make this page useful for Monday's meeting.", group: vagueGroup,
            passes: PageEvalChecks.staysRestrained),
    ]

    static let blockCap: [PageEvalTask] = [
        PageEvalTask(
            "one more block", "Add a count of facts by kind.", group: blockCapGroup, page: .eightBlocks,
            passes: PageEvalChecks.respectsBlockCap),
        PageEvalTask(
            "replace at the cap", "Replace your blockers list with a board of the blockers by person.",
            group: blockCapGroup, page: .eightBlocks
        ) { outcome in
            PageEvalChecks.isOneUpdateToBlockersBoard(
                of: outcome.startBlockID(titled: PageEvalPage.blockersTitle), outcome)
        },
    ]

    /// The store has no touched mark yet, so the request says it. The check is the one that is right after the mark
    /// exists: the old block stands as it was, and a board stands beside it. It is expected to fail until then.
    static let touched: [PageEvalTask] = [
        PageEvalTask(
            "touched block", "I arranged the blockers list myself. Change it to a board.", group: touchedGroup,
            page: .blockersList, isExpectedFailure: true
        ) { outcome in
            PageEvalChecks.leavesUnchanged(outcome.startBlockID(titled: PageEvalPage.blockersTitle), outcome)
                && PageEvalChecks.showsFactsView(outcome, layout: .board, filters: ["kind": ["blocker"]])
        }
    ]

    /// The deal-intake machine has company, sector, stage, from and rating. A claim is not a fact of the machine, and a
    /// view cannot filter by day, so the second and third tasks ask for what the catalog cannot show.
    static let fund: [PageEvalTask] = [
        PageEvalTask("hot deals by stage", "Show hot deals by stage.", group: fundGroup, facts: .fund) {
            PageEvalChecks.showsFactsView($0, groupBy: "stage", filters: ["rating": ["hot"]])
        },
        PageEvalTask(
            "claims unchecked", "Which claims are still unchecked?", group: fundGroup, facts: .fund,
            passes: PageEvalChecks.declinesToShow),
        PageEvalTask(
            "changed since monday", "What changed since Monday?", group: fundGroup, facts: .fund,
            passes: PageEvalChecks.answersWithoutDayFilter),
    ]
}
