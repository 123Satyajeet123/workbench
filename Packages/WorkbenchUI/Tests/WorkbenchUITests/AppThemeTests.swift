import AppKit
import Foundation
import Testing

@testable import WorkbenchUI

@MainActor struct AppThemeTests {
    @Test func systemFollowsMacOSAndLightAndDarkPinTheAppearance() {
        #expect(AppTheme.system.appearance == nil)
        #expect(AppTheme.light.appearance?.name == .aqua)
        #expect(AppTheme.dark.appearance?.name == .darkAqua)
    }

    @Test func anUnsetOrUnknownChoiceIsSystem() throws {
        let defaults = try #require(UserDefaults(suiteName: "wb-\(UUID().uuidString)"))
        #expect(AppTheme.saved(in: defaults) == .system)
        defaults.set("sepia", forKey: AppTheme.key)
        #expect(AppTheme.saved(in: defaults) == .system)
        defaults.set("dark", forKey: AppTheme.key)
        #expect(AppTheme.saved(in: defaults) == .dark)
    }
}
