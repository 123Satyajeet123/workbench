import SwiftUI
import WorkbenchCore

/// Adds a team: the templates with what each starts, a name, and after Add what was started, what the person still
/// chooses, and what was left out and why.
struct TeamSheet: View {
    @State private var model: TeamAddModel
    @Environment(\.dismiss) private var dismiss

    init(model: TeamAddModel) { _model = State(initialValue: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Add a team").textStyle(.title2, weight: .bold)
            ProblemSlotBanner(slot: model.problems)
            if let started = model.started {
                TeamStarted(model: model, started: started)
            } else {
                templates
            }
            HStack {
                Spacer()
                Button(model.started == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                if model.started == nil {
                    Button("Add", action: model.add).buttonStyle(.primary).keyboardShortcut(.defaultAction)
                        .disabled(!model.canAdd)
                }
            }
        }
        .padding(Space.l)
        .zoomedWidth(480)
    }

    @ViewBuilder private var templates: some View {
        @Bindable var model = model
        ScrollView {
            ChoiceList(items: model.templates, chosen: $model.chosen) { template in
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(template.name).textStyle(.headline)
                    Text(template.purpose).textStyle(.callout).foregroundStyle(.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.starts(template)).textStyle(.callout).foregroundStyle(.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxHeight: 360)
        TextField("Name", text: $model.name, prompt: Text(model.chosen?.name ?? "")).textFieldStyle(.roundedBorder)
    }

    private static func starts(_ template: TeamTemplate) -> String {
        template.machines.isEmpty
            ? "Starts nothing." : "Starts \(template.machines.map(\.name).formatted(.list(type: .and)))."
    }
}

/// What adding a team made. A team that starts nothing says so.
private struct TeamStarted: View {
    let model: TeamAddModel
    let started: TeamStart

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let folder = started.folder {
                Text("Added the team \(folder.name).").textStyle(.headline)
            } else {
                Text("Nothing was added.").textStyle(.headline)
                if started.items.isEmpty { Text("This template starts no machine.").text(.meta) }
            }
            ForEach(Array(started.items.enumerated()), id: \.offset) { _, item in
                Label(
                    item.refusal.map { "\(item.name) was left out. \($0)" } ?? "\(item.name) started.",
                    systemImage: item.refusal == nil ? "checkmark.circle" : "exclamationmark.circle"
                )
                .text(.meta)
            }
            if !model.choosers.isEmpty {
                Text("Choose what each machine reads.").text(.meta)
                SourceChoices(machines: model.choosers)
            }
        }
    }
}
