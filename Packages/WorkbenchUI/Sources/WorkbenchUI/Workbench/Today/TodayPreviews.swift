import SwiftUI
import WorkbenchCore

/// Today as a column on a page: a heading, then the sections. The previews and the render test show this.
struct TodayFrame: View {
    let model: TodayModel
    var brief: MorningBrief?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Today").textStyle(.largeTitle, weight: .bold)
            TodayBody(model: model, brief: brief)
        }
        .padding(Space.page)
        .frame(width: Page<EmptyView, EmptyView>.columnWidth + 2 * Space.page, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// A scratch session, with the sample day when asked. Nothing here touches the founder's store.
private struct ScratchSession<Content: View>: View {
    let sample: Bool
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
        try? await TodaySample.populate(store: session.store, crew: session.crew)
        session.today.refresh()
    }
}

#Preview("Today, a sample day") {
    ScratchSession(sample: true) { TodayFrame(model: $0.today) }
}

#Preview("Today, an empty day") {
    ScratchSession(sample: false) { TodayFrame(model: $0.today) }
}

#Preview("People, a sample day") {
    ScratchSession(sample: true) { session in
        FactGroupsBody(groups: session.today.people, empty: FactGroupsPage.Lens.people.empty, model: session.today)
            .padding().frame(width: 760)
    }
}

#Preview("Projects, a sample day") {
    ScratchSession(sample: true) { session in
        FactGroupsBody(
            groups: session.today.projectGroups, empty: FactGroupsPage.Lens.projects.empty, model: session.today
        )
        .padding().frame(width: 760)
    }
}
