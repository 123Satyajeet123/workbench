import Foundation
import Kernel
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor
@Suite struct AddFactTests {
    private let today = WorkDay(containing: Date(timeIntervalSince1970: 1_790_000_000))

    private final class Added { var facts: [HandFact] = [] }

    private func model(_ added: Added? = nil, fail: Bool = false) -> AddFactModel {
        AddFactModel(spec: .team, people: ["Asha"], project: "Bolt Pay", today: today) { fact in
            if fail { throw CocoaError(.fileWriteUnknown) }
            added?.facts.append(fact)
        }
    }

    @Test func theKindsAreTheMachinesOwnAndTheFirstIsChosen() {
        let sheet = model()
        #expect(sheet.kinds == HelperSpec.team.factKinds && sheet.kind == "plan")
    }

    @Test func theSheetAddsOnlyWhenItHasWords() {
        let sheet = model()
        #expect(!sheet.canAdd && !sheet.submit())
        sheet.words = "  "
        #expect(!sheet.canAdd)
        sheet.words = "Send the deck"
        #expect(sheet.canAdd)
    }

    @Test func submitHandsOverTheFieldsAndTheDueDay() {
        let added = Added()
        let sheet = model(added)
        sheet.words = "Send the deck"
        sheet.kind = "commitment"
        sheet.person = " Meera "
        sheet.due = .tomorrow
        #expect(sheet.submit())
        #expect(
            added.facts
                == [
                    HandFact(
                        kind: "commitment", text: "Send the deck", person: "Meera", project: "Bolt Pay",
                        due: today.adding(days: 1))
                ])
    }

    @Test func aFailureStaysOnTheSheetWithAPlainProblem() {
        let sheet = model(fail: true)
        sheet.words = "Send the deck"
        #expect(!sheet.submit() && sheet.problem == "Could not add the fact. Try again.")
    }

    @Test func theDueChoicesCountFromTodayAndNoDayGivesNone() {
        #expect(DueChoice.none.day(from: today) == nil && DueChoice.today.day(from: today) == today)
        #expect(DueChoice.nextWeek.day(from: today) == today.adding(days: 7))
        #expect(DueChoice.day(today.adding(days: 3)).day(from: today) == today.adding(days: 3))
    }

    @Test func aFactAddedThroughTheSheetIsAnItemOfThePersonsOwnWords() throws {
        let store = try scratchStore(clock: { Date(timeIntervalSince1970: 1_790_000_000) })
        let sheet = AddFactModel(spec: .team, project: "Bolt Pay", today: today) {
            _ = try store.addFact($0, owner: PersonID("test-owner"))
        }
        sheet.words = "Call the bank"
        #expect(sheet.submit())
        let item = try #require(try store.queries.items(of: HelperSpec.team.task, on: today).first)
        #expect(item.run == nil && item.authority == .ownWords && item["project"] == "Bolt Pay")
    }
}
