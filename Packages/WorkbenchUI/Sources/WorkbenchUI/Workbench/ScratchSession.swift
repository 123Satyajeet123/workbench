import SwiftUI
import WorkbenchCore

/// A scratch session, with the sample day when asked. Nothing here touches the founder's store.
struct ScratchSession<Content: View>: View {
    var sample = true
    var withSummaries = true
    @ViewBuilder let content: (AppSession) -> Content
    @State private var launch = AppLaunch.start(
        storeFolder: FileManager.default.temporaryDirectory.appending(path: "workbench-preview-\(UUID().uuidString)"))

    var body: some View {
        switch launch {
        case .ready(let session):
            content(session)
                .environment(session)
                .task { if sample { await populate(session) } }
        case .failed(let failure):
            Text(failure.cause)
        }
    }

    private func populate(_ session: AppSession) async {
        try? await TodaySample.populate(store: session.store, crew: session.crew, withSummaries: withSummaries)
        session.today.refresh()
    }
}
