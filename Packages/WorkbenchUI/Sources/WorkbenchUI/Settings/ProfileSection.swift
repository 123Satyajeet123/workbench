import SwiftUI

/// The one way into the demo, and the one way back. Switching restarts the app and changes no data.
struct ProfileSection: View {
    let profile: Profile
    let reading: [String]

    private var target: Profile { profile.isDemo ? .yours : .demo }

    private var detail: String {
        target.isDemo && !ProfileSwitch.demoIsBuilt
            ? "The demo is not on this Mac yet." : ProfileSwitch.sentence(to: target)
    }

    var body: some View {
        Section("Demo") {
            SettingRow(profile.isDemo ? ProfileSwitch.demoLabel : "Synthetic data", detail) {
                Button(ProfileSwitch.title(to: target)) { ProfileSwitch.go(to: target) }
                    .disabled(target.isDemo && !ProfileSwitch.demoIsBuilt)
            }
            if let warning = ProfileSwitch.readingWarning(machines: reading) { FormNote(warning) }
        }
    }
}
