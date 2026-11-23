import AgentCLI
import SwiftUI
import WorkbenchCore

/// What the reader is, before the first call: the Claude tool's state, and the two conditions of reading with a plan.
struct ModelReaderRows: View {
    let store: Store
    let kind: AgentCLIKind
    var readStatus: @Sendable (Store) async -> ReaderStatus = { store in
        await ReaderProbe(workDirectory: store.directory.appending(path: "agent-work")).status()
    }
    @State private var status: ReaderStatus?
    @State private var confirmation: ModelTermsConfirmation?

    var body: some View {
        Group {
            if kind == .claude {
                SettingRow("Reader", status.map(Self.describe) ?? "Checking…") { EmptyView() }
            }
            SettingRow("I confirm both conditions", Self.conditions) {
                Toggle("I confirm both conditions", isOn: confirmed).labelsHidden().toggleStyle(.switch)
            }
            if let confirmation {
                FormNote("Confirmed on \(confirmation.confirmedAt.formatted(date: .abbreviated, time: .omitted)).")
            } else {
                FormNote("Workbench makes no call with your plan until you confirm.")
            }
        }
        .task(id: kind) {
            confirmation = store.currentModelTermsConfirmation()
            if kind == .claude { status = await readStatus(store) }
        }
    }

    private static let conditions = ModelTerms.conditions.map { "• \($0)" }.joined(separator: "\n")

    private var confirmed: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { yes in
                try? yes ? store.confirmModelTerms() : store.withdrawModelTerms()
                confirmation = store.currentModelTermsConfirmation()
            })
    }

    static func describe(_ status: ReaderStatus) -> String {
        guard status.installedAt != nil else { return "The claude tool is not installed on this Mac." }
        let version = status.version.map { "Claude \($0)" } ?? "Claude"
        switch status.signedIn {
        case true?: return "\(version), signed in\(Self.plan(status))."
        case false?: return "\(version), not signed in. Run claude and sign in."
        case nil: return "\(version), sign-in not known."
        }
    }

    private static func plan(_ status: ReaderStatus) -> String {
        let named = status.planTier ?? status.subscriptionType ?? ""
        return named.isEmpty ? "" : " with your \(named) plan"
    }
}
