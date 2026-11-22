import SwiftUI
import WorkbenchCore

struct ConnectList: View {
    let facts: ConnectFacts
    let needs: [SourceNeed]
    var isChecklist = false

    @Environment(MacAccess.self) private var access
    @Environment(CaptureSettings.self) private var capture
    @Environment(TodayModel.self) private var today
    @Environment(Crew.self) private var crew
    @Environment(ModelSettings.self) private var models
    @Environment(BrowserSetup.self) private var browsers
    @State private var choosingChats = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                ConnectRowView(
                    name: name(of: row), detail: isChecklist ? nil : detail(of: row), status: facts.status(of: row),
                    actions: isChecklist ? [] : action(for: row).map { [$0] } ?? []
                ) {
                    icon(of: row)
                }
                if row != rows.last || facts.needsBrowser { Divider() }
            }
            if facts.needsBrowser { BrowserRows(facts: facts, isChecklist: isChecklist) }
        }
        .padding(.horizontal, Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
        .sheet(isPresented: $choosingChats) {
            if let pip = crew.team, let source = pip.source as? WhatsAppSource {
                ChatsSheet(pip: pip, source: source)
            }
        }
    }

    private var rows: [ConnectRow] { ConnectRow.rows(for: needs) }

    private func source(of row: ConnectRow) -> CaptureSource? {
        CaptureSource.all.first { $0.source == row.kind }
    }

    private func name(of row: ConnectRow) -> String {
        row.sourceName ?? (models.choice.kind == .claude ? "Claude Code" : "Codex")
    }

    private func reason(of row: ConnectRow) -> String {
        guard let need = needs.first(where: { ConnectRow($0.kind) == row }) else { return "" }
        return "\(need.machine): \(need.reason)"
    }

    private func detail(of row: ConnectRow) -> String {
        switch row {
        case .reader:
            facts.status(of: .reader).isDone
                ? "Reads what you allow, with your own sign-in."
                : "Install it and sign in, then check again."
        case .whatsApp:
            facts.status(of: .whatsApp) == .needsPermission(pane: .fullDiskAccess)
                ? "Turn on Workbench in Full Disk Access. macOS then asks to quit and reopen; setup opens here again."
                : reason(of: row) + (crew.team == nil ? " You choose the group on its page after setup." : "")
        case .mail: reason(of: row) + " You name the Gmail label on its page."
        case .screen, .screenText, .web, .calendar, .calls: reason(of: row)
        }
    }

    @ViewBuilder private func icon(of row: ConnectRow) -> some View {
        switch row {
        case .reader: Image(systemName: "terminal").foregroundStyle(.iconTint)
        case .screen: Mascot(look: .mochi, size: 28)
        case .whatsApp: Mascot(look: .pip, size: 28)
        case .calls: Mascot(look: .echo, size: 28)
        case .web: Image(systemName: "globe").foregroundStyle(.iconTint)
        case .screenText, .mail, .calendar: Image(systemName: source(of: row)?.symbol ?? "").foregroundStyle(.iconTint)
        }
    }

    private func action(for row: ConnectRow) -> ConnectAction? {
        switch (row, facts.status(of: row)) {
        case (_, .needsPermission(let pane)):
            .init(title: "Open System Settings", isPrimary: true) { SystemSettings.open(pane: pane) }
        case (.reader, .missing):
            .init(title: "Check again", isPrimary: false) { access.recheck(reader: models.choice.kind) }
        case (.whatsApp, .off) where crew.team != nil:
            .init(title: "Choose a group", isPrimary: true) { choosingChats = true }
        case (.whatsApp, .chosen):
            .init(title: "Change", isPrimary: false) { choosingChats = true }
        case (_, .off):
            row.kindToTurnOn.map { kind in .init(title: "Turn on", isPrimary: true) { turnOn(kind) } }
        default: nil
        }
    }

    private func turnOn(_ kind: SourceKind) {
        capture.set(kind, on: true)
        Task {
            _ = await capture.askForAccess(kind, today: today)
            access.recheck(reader: models.choice.kind)
        }
    }
}

struct ConnectAction: Identifiable {
    let title: String
    let isPrimary: Bool
    let perform: () -> Void

    var id: String { title }
}

struct ConnectRowView<Icon: View>: View {
    let name: String
    let detail: String?
    let status: ConnectStatus
    let actions: [ConnectAction]
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: Space.m) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(name).textStyle(.headline)
                if let detail {
                    Text(detail).textStyle(.callout).foregroundStyle(.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !actions.isEmpty, tone == .attention { statusLabel }
            }
            Spacer(minLength: Space.m)
            if actions.isEmpty {
                statusLabel.frame(maxWidth: 200, alignment: .trailing)
            } else {
                ViewThatFits(in: .horizontal) {
                    actionButtons(HStackLayout(spacing: Space.s))
                    actionButtons(VStackLayout(alignment: .trailing, spacing: Space.xs))
                }
            }
        }
        .padding(.vertical, detail == nil ? Space.s : Space.m)
    }

    private func actionButtons(_ layout: some Layout) -> some View {
        layout {
            ForEach(actions) { action in
                if action.isPrimary {
                    Button(action.title, action: action.perform).buttonStyle(.primary)
                } else {
                    Button(action.title, action: action.perform).buttonStyle(.ghost).foregroundStyle(.linkText)
                }
            }
        }
        .fixedSize()
    }

    private var statusLabel: some View {
        Label {
            Text(status.title).foregroundStyle(.supporting).lineLimit(1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone.color)
        }
        .textStyle(.callout)
    }

    private var symbol: String {
        switch status {
        case .ready, .chosen: "checkmark.circle.fill"
        case .needsPermission, .missing, .waiting: "exclamationmark.circle.fill"
        case .off: "circle"
        }
    }

    private var tone: Tone {
        switch status {
        case .ready, .chosen: .good
        case .needsPermission, .missing, .waiting: .attention
        case .off: .neutral
        }
    }
}

private struct ChatsSheet: View {
    let pip: HelperModel
    let source: WhatsAppSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                Mascot(look: .pip, size: 36)
                Text("What \(pip.name) reads").textStyle(.title2, weight: .bold)
            }
            .padding(Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ProblemSlotBanner(slot: pip.problems)
                    GroupChooser(model: pip, source: source)
                }
                .padding([.horizontal, .bottom], Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .frame(width: 520, height: 560)
        .background(.pageFill)
        .onChange(of: source.chats.map(\.id)) { dismiss() }
        .task {
            pip.problems.dismiss()
            guard source.groups.isEmpty, source.direct.isEmpty else { return }
            pip.attempt("list your WhatsApp chats", source.loadGroups)
        }
    }
}

/// One row for each Chromium browser on this Mac, or one row that says there is none.
private struct BrowserRows: View {
    let facts: ConnectFacts
    let isChecklist: Bool
    @Environment(BrowserSetup.self) private var setup

    var body: some View {
        if facts.browsers.isEmpty {
            row(
                name: "Browser", detail: "Install a Chromium browser and open it once. Then check again.",
                status: .missing, actions: [.init(title: "Check again", isPrimary: false) { setup.recheck() }])
        }
        ForEach(facts.browsers) { browser in
            row(
                name: browser.name, detail: detail(of: browser), status: facts.status(of: browser),
                actions: actions(for: browser))
            if browser != facts.browsers.last { Divider() }
        }
    }

    private func row(
        name: String, detail: String, status: ConnectStatus, actions: [ConnectAction] = []
    ) -> some View {
        ConnectRowView(
            name: name, detail: isChecklist ? nil : detail, status: status, actions: isChecklist ? [] : actions
        ) {
            Image(systemName: "globe").foregroundStyle(.iconTint)
        }
    }

    private func detail(of browser: BrowserFact) -> String {
        switch facts.status(of: browser) {
        case .ready: "The extension reads pages for you. Pages stay on this Mac."
        case .waiting:
            "Press the button: it opens the extensions page and the Extension folder. Turn on Developer mode, choose Load unpacked, and pick the Extension folder. This row turns green by itself."
        default: "Workbench reads pages only in a browser you turn on."
        }
    }

    private func actions(for browser: BrowserFact) -> [ConnectAction] {
        guard let installed = setup.installed.first(where: { $0.id == browser.id }) else { return [] }
        switch facts.status(of: browser) {
        case .off:
            return [.init(title: "Turn on", isPrimary: true) { setup.turn(installed, on: true) }]
        case .waiting:
            return [
                .init(title: "Open extensions page", isPrimary: true) { setup.startLoading(in: installed) }
            ]
        default: return []
        }
    }
}
