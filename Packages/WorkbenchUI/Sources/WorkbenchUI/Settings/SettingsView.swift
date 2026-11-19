import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Capture", systemImage: "eye") { CaptureSettingsView() }
            Tab("Team", systemImage: "person.3") { TeamSettingsView() }
        }
        .frame(width: 640, height: 600)
    }
}
