import SwiftUI

struct UpdateBanner: View {
    let name: String
    let changes: [String]
    let update: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("A newer \(name) is ready").textStyle(.headline)
                Text("It \(changes.formatted(.list(type: .and))). Your items and marks stay; its trust starts again.")
                    .textStyle(.callout).foregroundStyle(.supporting)
            }
            Spacer()
            Button("Update", action: update).buttonStyle(.primary)
        }
        .padding(Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }
}
