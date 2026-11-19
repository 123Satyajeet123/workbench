import SwiftUI

struct AccountsSettingsView: View {
    @Environment(GoogleAccountsModel.self) private var google

    var body: some View {
        Form {
            Section {
                ForEach(google.accounts, id: \.self) { email in
                    LabeledContent(email) {
                        Button("Disconnect") { Task { await google.disconnect(email) } }
                    }
                    Toggle(
                        "Allow reading my “Workbench” mail label",
                        isOn: Binding {
                            google.readsLabel(of: email)
                        } set: {
                            google.setReadsLabel($0, of: email)
                        }
                    )
                    .disabled(google.isConnecting)
                }
                GoogleConnectButton(google: google, title: "Connect a Google account")
            } header: {
                Text("Google")
            } footer: {
                FormNote(
                    google.problem
                        ?? "Connecting gives Workbench access to your calendar, and to mail only if you allow the label. Workbench does not read either yet. Tokens stay in this Mac’s Keychain."
                )
            }
        }
        .formStyle(.grouped)
    }
}
