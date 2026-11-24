import SwiftUI
import WorkbenchCore

/// The team's name and people, the template the team starts from, and the gallery items that template sets up.
struct TeamStep: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        @Bindable var team = model.teamModel
        VStack(alignment: .leading, spacing: Space.l) {
            TeamEditor()
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Start from").textStyle(.headline)
                if !model.startsTeam {
                    Text("This Mac already has machines. Workbench keeps them and adds none from a template.")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
                ChoiceList(items: team.templates, chosen: $team.template) { template in
                    VStack(alignment: .leading, spacing: Space.xs / 2) {
                        Text(template.name).textStyle(.headline)
                        Text(template.purpose).textStyle(.callout).foregroundStyle(.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.startsTeam, let chosen = team.template { TemplateItems(template: chosen) }
            }
        }
    }
}

/// What a team template sets up, item by item, and the optional items the person may add.
private struct TemplateItems: View {
    let template: TeamTemplate
    @Environment(OnboardingModel.self) private var model

    private var optionalItems: [(machine: TeamMachine, item: GalleryTemplate)] {
        template.optionalMachines.compactMap { machine in GalleryTemplate.of(id: machine.template).map { (machine, $0) }
        }
    }

    var body: some View {
        if !template.items.isEmpty || !optionalItems.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("What \(template.name) sets up").textStyle(.headline)
                ForEach(template.items) { GalleryItemLabel(template: $0) }
                ForEach(optionalItems, id: \.machine.template) { machine, item in
                    Toggle(
                        isOn: Binding(
                            get: { model.optionalChosen.contains(machine.template) },
                            set: { model.include(machine, $0) })
                    ) {
                        GalleryItemLabel(template: item)
                    }
                    .toggleStyle(.switch)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
        }
    }
}
