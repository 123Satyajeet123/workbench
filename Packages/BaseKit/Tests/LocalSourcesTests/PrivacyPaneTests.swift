import Testing

@testable import LocalSources

@Suite struct PrivacyPaneTests {
    @Test func eachPaneOpensItsPlaceInPrivacyAndSecurity() {
        #expect(
            PrivacyPane.fullDiskAccess.url.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        #expect(PrivacyPane.accessibility.rawValue == "Privacy_Accessibility")
        #expect(PrivacyPane.microphone.rawValue == "Privacy_Microphone")
        #expect(PrivacyPane.calendars.rawValue == "Privacy_Calendars")
        #expect(PrivacyPane.reminders.rawValue == "Privacy_Reminders")
    }
}
