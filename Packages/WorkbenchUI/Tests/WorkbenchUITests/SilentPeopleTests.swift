import Testing

@testable import WorkbenchUI

struct SilentPeopleTests {
    private let names = (1...12).map { "Person \($0)" }

    @Test func aLongListShowsTheFirstFewAndCountsTheRest() {
        #expect(
            SilentPeople.line(names, showsAll: false)
                == "Person 1, Person 2, Person 3, Person 4, Person 5, Person 6, Person 7, Person 8 and 4 more")
        #expect(SilentPeople.line(names, showsAll: true).hasSuffix("Person 11, and Person 12"))
    }

    @Test func aShortListShowsEveryone() {
        #expect(SilentPeople.line(["Asha", "Ravi"], showsAll: false) == "Asha and Ravi")
    }
}
