import SwiftUI
import WorkbenchCore

/// The team's name and people, and the template the team starts from.
struct TeamStep: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            TeamEditor()
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Start from").textStyle(.headline)
                if !model.startsTeam {
                    Text("This Mac already has machines. Workbench keeps them and adds none from a template.")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
                VStack(spacing: 0) {
                    ForEach(model.teamModel.templates) { template in
                        TemplateRow(
                            template: template, isChosen: template == model.template,
                            choose: { model.teamModel.template = template })
                        if template != model.teamModel.templates.last { Divider() }
                    }
                }
                .padding(.horizontal, Space.m)
                .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
            }
        }
    }
}

private struct TemplateRow: View {
    let template: TeamTemplate
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Space.m) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isChosen ? Color.accentFill : Color.bodyText.opacity(0.4))
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(template.name).textStyle(.headline)
                    Text(template.purpose).textStyle(.callout).foregroundStyle(.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
