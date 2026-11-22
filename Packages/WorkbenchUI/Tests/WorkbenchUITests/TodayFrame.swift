import SwiftUI
import WorkbenchCore

@testable import WorkbenchUI

/// Today as a column on a page: a heading, then the sections. The render tests show this.
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
