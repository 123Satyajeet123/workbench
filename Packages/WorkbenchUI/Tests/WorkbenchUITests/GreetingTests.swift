import Foundation
import Testing

@testable import WorkbenchUI

struct GreetingTests {
    private func at(_ hour: Int) throws -> Date {
        try #require(Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: .now))
    }

    @Test func theGreetingFollowsThePartOfTheDayAndUsesTheNameWhenThereIsOne() throws {
        let named = Identity(name: "Shivansh")
        #expect(named.greeting(at: try at(11)) == "Good morning, Shivansh")
        #expect(named.greeting(at: try at(12)) == "Good afternoon, Shivansh")
        #expect(named.greeting(at: try at(17)) == "Good evening, Shivansh")
        #expect(Identity(name: "  ").greeting(at: try at(9)) == "Good morning")
    }
}
