import Kernel
import Testing

/// The label id is signed into every event header, and the source id names a source inside it.
@Suite struct LabelIDTests {
    @Test func theIdDoesNotDependOnHowTheLabelWasBuilt() {
        let group = Label(source: Team.foundersGroup, classes: [sourceClass("chat")])
        let screen = Label(source: Team.founderScreen, classes: [sourceClass("personal")])
        #expect(group.joined(with: screen).id == screen.joined(with: group).id)
        #expect(group.joined(with: [screen, group, screen]).id == group.joined(with: screen).id)
    }

    @Test func anyOtherSourceOrClassGivesAnotherId() {
        let base = Label(source: Team.foundersGroup, classes: [sourceClass("chat")])
        #expect(base.id != Label(source: Team.foundersGroup).id)
        #expect(base.id != Label(source: Team.founderScreen, classes: [sourceClass("chat")]).id)
        #expect(base.id == Label(source: Team.foundersGroup, classes: [sourceClass("chat")]).id)
    }

    /// Pinned, and computed apart from this code (Python hashlib over the same framing), so a change to the source
    /// id or label id layout cannot pass unnoticed: every stored stream would move.
    @Test func theIdLayoutIsPinned() {
        #expect(Team.foundersGroup.description == "eb268095fc85ab9ec4293c70e60d729a")
        #expect(Label(source: Team.foundersGroup).id.description == "e30b2bc17e219edaa1565be296ec7a20")
    }
}
