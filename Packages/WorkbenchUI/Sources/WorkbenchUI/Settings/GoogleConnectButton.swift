import SwiftUI

struct GoogleConnectButton: View {
    let google: GoogleAccountsModel
    let title: String

    var body: some View {
        if google.isConnecting {
            HStack {
                ProgressView().controlSize(.small)
                Text("Finish the sign-in in your browser.")
                Button("Cancel") { google.cancelConnect() }
            }
        } else {
            Button(title) { google.connect() }
                .disabled(!google.canConnect)
        }
    }
}
