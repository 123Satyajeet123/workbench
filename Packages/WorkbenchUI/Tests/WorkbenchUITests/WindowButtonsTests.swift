import CoreGraphics
import Testing

@testable import WorkbenchUI

struct WindowButtonsTests {
    private let close = CGRect(x: 13, y: 773, width: 14, height: 14)
    private let zoom = CGRect(x: 53, y: 773, width: 14, height: 14)

    @Test func inAWindowTheBarCentresOnTheButtonsAndStartsAfterThem() {
        let buttons = WindowButtons.measure(
            contentHeight: 800, close: close, zoom: zoom, inWindow: true, isFullScreen: false)
        #expect(buttons == WindowButtons(center: 20, trailing: 67))
    }

    @Test func inFullScreenTheButtonsLiveElsewhereSoTheBarKeepsItsHeightAndNeedsNoRoomForThem() {
        let far = CGRect(x: 13, y: 8, width: 14, height: 14)
        for (inWindow, isFullScreen) in [(false, true), (true, true), (false, false)] {
            let buttons = WindowButtons.measure(
                contentHeight: 1117, close: far, zoom: far, inWindow: inWindow, isFullScreen: isFullScreen)
            #expect(buttons == .hidden && buttons.center == WindowButtons.compact.center)
        }
    }
}
