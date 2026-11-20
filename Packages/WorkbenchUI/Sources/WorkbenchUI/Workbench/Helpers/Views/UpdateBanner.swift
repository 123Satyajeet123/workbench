import SwiftUI

/// A newer built-in design is ready for this machine. Taking it is the founder's act: the brief and checks change,
/// the items and marks stay, and trust is earned again on the new version.
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
            Button("Update", action: update).buttonStyle(.borderedProminent)
        }
        .padding(Space.m)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}
