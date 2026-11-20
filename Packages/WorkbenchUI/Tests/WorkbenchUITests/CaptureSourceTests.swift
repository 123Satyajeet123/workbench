import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct CaptureSourceTests {
    @Test func whatThePersonTypedIsNotACaptureSwitch() {
        #expect(!CaptureSource.all.map(\.source).contains(.typed))
        #expect(!CapturePolicy().isEnabled(.typed))
    }
}
