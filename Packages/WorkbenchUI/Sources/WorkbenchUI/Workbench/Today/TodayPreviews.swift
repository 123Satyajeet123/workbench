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
        .background(.pageFill)
    }
}

#Preview("Today, a sample day") {
    ScratchSession(sample: true) { TodayFrame(model: $0.today) }
}

#Preview("Today, facts without summaries") {
    ScratchSession(withSummaries: false) { TodayFrame(model: $0.today) }
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
