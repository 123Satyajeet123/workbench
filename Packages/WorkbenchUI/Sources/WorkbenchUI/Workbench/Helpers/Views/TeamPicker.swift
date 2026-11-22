import LocalSources
import SwiftUI

struct TeamPicker: View {
    let model: HelperModel
    let source: WhatsAppSource
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Your team").textStyle(.headline)
            Text(
                "Tick the people on your team. \(model.name) expects updates only from them. With nobody ticked, it expects everyone in the chats."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            if source.members.isEmpty {
                Text("No members known yet. They appear after the first reading.")
                    .textStyle(.callout).foregroundStyle(.supporting)
            } else {
                if source.members.count > 8 {
                    TextField("Search people", text: $query, prompt: Text("Search people"))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                }
                ForEach(FuzzySearch.filter(source.members, by: query, name: \.name), id: \.jid) { member in
                    Toggle(member.name, isOn: ticked(member)).toggleStyle(.checkbox)
                }
            }
        }
        .textStyle(.body)
    }

    private func ticked(_ member: WhatsAppMember) -> Binding<Bool> {
        Binding(
            get: { source.isTeammate(member) },
            set: { on in model.attempt("save your team") { try source.setTeammate(member, on: on) } })
    }
}
