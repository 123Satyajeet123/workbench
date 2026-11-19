import SwiftUI

struct LoginItemToggle: View {
    @State private var isOn = LoginItem.isOn
    @State private var failure: String?

    var body: some View {
        Toggle("Open Workbench at login", isOn: $isOn)
            .onChange(of: isOn) { _, on in
                do {
                    try LoginItem.set(on)
                    failure = nil
                } catch {
                    isOn = LoginItem.isOn
                    failure = error.localizedDescription
                }
            }
        if let failure { Text(failure).foregroundStyle(.supporting) }
    }
}
