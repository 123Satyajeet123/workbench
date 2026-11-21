import AppKit
import SwiftUI

struct StartupErrorView: View {
    let failure: StartupFailure

    var body: some View {
        VStack(spacing: Space.m) {
            Text("Workbench cannot open its store").textStyle(.title2, weight: .bold)
            Text(failure.cause).foregroundStyle(.supporting).textSelection(.enabled)
            Text(failure.storeFolder.path).textStyle(.caption).foregroundStyle(.supporting).textSelection(.enabled)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .multilineTextAlignment(.center)
        .padding(Space.page)
        .frame(minWidth: 480, minHeight: 280)
        .background(.pageFill)
    }
}
