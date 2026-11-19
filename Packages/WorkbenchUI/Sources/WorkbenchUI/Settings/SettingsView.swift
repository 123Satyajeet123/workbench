import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Capture", systemImage: "eye") { CaptureSettingsView() }
            Tab("Accounts", systemImage: "person.crop.circle") { AccountsSettingsView() }
        }
        .frame(width: 640, height: 600)
    }
}
