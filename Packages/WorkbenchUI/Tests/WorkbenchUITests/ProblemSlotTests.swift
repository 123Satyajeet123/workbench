import LocalSources
import Testing

@testable import WorkbenchUI

@MainActor struct ProblemSlotTests {
    @Test func whatsAppRefusedByMacOSPointsAtFullDiskAccess() {
        let slot = ProblemSlot()
        slot.report("list your WhatsApp groups", ReadError.notPermitted)
        #expect(slot.settingsPane == "Privacy_AllFiles")
        #expect(slot.text?.contains("Full Disk Access") == true)
    }

    @Test func otherProblemsPointNowhereAndADismissClearsThePointer() {
        let slot = ProblemSlot()
        slot.report("list your WhatsApp groups", ReadError.storeMissing)
        #expect(slot.settingsPane == nil && slot.text?.contains("Install the app") == true)
        slot.report("read the day", ReadError.notPermitted)
        slot.dismiss()
        #expect(slot.settingsPane == nil && slot.text == nil)
        slot.report("read the day", ReadError.notPermitted)
        slot.attempt("read the day", clearing: true) {}
        #expect(slot.settingsPane == nil && slot.text == nil)
    }
}
