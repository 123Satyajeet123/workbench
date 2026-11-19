import Foundation
import Testing
import WorkbenchCore

@testable import CaptureService

struct CallStartWordsTests {
    @Test func theSwitchedOffSourceNamesTheSettingToTurnOn() {
        let error = CallStartError.denied(.sourceSwitchedOff)
        #expect(error.localizedDescription == "Turn on “Record calls I start” in Settings > General.")
        #expect(error.needsCallSwitch)
    }

    @Test func otherRefusalsReadAsPlainSentencesAndNeedNoSwitch() {
        let others: [CallStartError] = [
            .needsConfirmation, .denied(.captureOff), .denied(.paused), .denied(.privateMode),
            .denied(.labelDenied), .denied(.labelNotAllowed),
        ]
        for error in others {
            #expect(!error.needsCallSwitch)
            #expect(!error.localizedDescription.contains("CallStartError"))
        }
    }
}
