import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct CrewCardTests {
    @Test func aMachineThatEarnedTrustSaysHowRightItWasAndThatItRunsOnItsOwn() {
        #expect(
            CrewCardFacts.health(right: 28, of: 29, trust: .earned(bound: 0.08))
                == "Right 28 of 29 you checked; trusted (provisional)")
    }

    @Test func aMachineThatNeedsMoreChecksSaysHowMany() {
        #expect(
            CrewCardFacts.health(right: 5, of: 6, trust: .needsMore(12))
                == "Right 5 of 6 you checked; needs 12 more checks before it is trusted")
        #expect(
            CrewCardFacts.health(right: 0, of: 0, trust: .needsMore(1))
                == "Needs 1 more check before it is trusted")
    }
}
