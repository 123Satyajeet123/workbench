import Testing

@testable import WorkbenchUI

@Suite struct MotionTests {
    @Test func nothingMovesWithReduceMotionOn() {
        #expect(Motion.settle(reduceMotion: true) == nil)
    }

    @Test func aChangeSettlesInsideTwoHundredToThreeHundredFiftyMillisecondsEaseInOut() {
        #expect((0.2...0.35).contains(Motion.duration))
        #expect(Motion.settle(reduceMotion: false) == .easeInOut(duration: Motion.duration))
    }
}
