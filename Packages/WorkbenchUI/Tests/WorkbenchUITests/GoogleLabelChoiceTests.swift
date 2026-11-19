import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct GoogleLabelChoiceTests {
    private let key = "googleLabelReading"

    @Test func aStoredChoiceIsLoadedAndTurningItOffIsKept() throws {
        let store = try scratchStore()
        try store.saveState(#"["ann@example.com"]"#, forKey: key)
        let model = GoogleAccountsModel(store: store)
        #expect(model.readsLabelFor == ["ann@example.com"])
        model.setReadsLabel(false, of: "ann@example.com")
        #expect(model.readsLabelFor.isEmpty)
        #expect(GoogleAccountsModel(store: store).readsLabelFor.isEmpty)
    }

    @Test func aChoiceWithoutGoogleAllowingMailIsNeverReadAsOn() throws {
        let store = try scratchStore()
        try store.saveState(#"["ann@example.com"]"#, forKey: key)
        #expect(!GoogleAccountsModel(store: store).readsLabel(of: "ann@example.com"))
    }

    @Test func aStoredChoiceThatCannotBeReadIsShownAsAProblem() throws {
        let store = try scratchStore()
        try store.saveState("not json", forKey: key)
        #expect(GoogleAccountsModel(store: store).problem != nil)
        #expect(GoogleAccountsModel(store: try scratchStore()).readsLabelFor.isEmpty)
    }
}
