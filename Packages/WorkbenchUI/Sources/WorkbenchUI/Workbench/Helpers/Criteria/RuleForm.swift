import SwiftUI
import WorkbenchCore

/// The form for one rule: its kind, its role, and the words or the number it tests.
struct RuleForm: View {
    @Binding var draft: RuleDraft
    let commit: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(RuleDraft.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 280)
                Picker("Role", selection: $draft.role) {
                    ForEach(Rule.Role.allCases, id: \.self) { Text($0.words).tag($0) }
                }
                .frame(maxWidth: 190)
            }
            if draft.kind == .number { numberFields } else { textField }
            Text(roleHelp).textStyle(.caption).foregroundStyle(.supporting)
            HStack {
                Button(draft.editing == nil ? "Add rule" : "Update rule", action: commit)
                    .disabled(draft.rule() == nil)
                Button("Cancel", action: cancel)
            }
        }
        .padding(Space.m)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }

    private var numberFields: some View {
        HStack(spacing: Space.s) {
            TextField("What to measure, such as employee count", text: $draft.measure).frame(maxWidth: 260)
            Picker("Comparison", selection: $draft.comparison) {
                ForEach(Comparison.allCases, id: \.self) { Text($0.words).tag($0) }
            }
            .labelsHidden().frame(width: 110)
            TextField("Number", text: $draft.low).frame(width: 80)
            if draft.comparison == .between {
                Text("and")
                TextField("Number", text: $draft.high).frame(width: 80)
            }
            TextField("Unit", text: $draft.unit).frame(width: 110)
        }
    }

    private var textField: some View {
        TextField(
            draft.kind == .want
                ? "What you want, such as B2B software in India" : "What you do not want, such as gambling",
            text: $draft.says)
    }

    private var roleHelp: String {
        switch draft.role {
        case .must: "Must: if it fails, the deal is cold. If it is unknown, the deal is at most warm."
        case .plus: "Plus: each plus that passes adds a point."
        case .minus: "Minus: each minus that fails takes a point away."
        case .dealBreaker: "Deal-breaker: if it fails, the deal is cold, whatever else passes."
        }
    }
}
