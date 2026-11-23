import LocalSources
import SwiftUI
import WorkbenchCore

extension SidebarSelection {
    /// The key that goes to this page, with ⌘. Fixed, so it does not move when machines come and go.
    var goKey: KeyEquivalent? {
        switch self {
        case .day: "1"
        case .review: "2"
        case .people: "3"
        case .projects: "4"
        case .calls: "5"
        case .deals: "6"
        case .catalog: "7"
        case .mochi, .crew, .advanced, .machine: nil
        }
    }
}

/// The lines of ⌘K, built from values.
enum PaletteEntries {
    static func commands(
        sections: [SidebarSection], capture: CaptureMode, isRecording: Bool
    ) -> [PaletteEntry] {
        pages(sections) + actions(capture: capture, isRecording: isRecording)
    }

    private static func pages(_ sections: [SidebarSection]) -> [PaletteEntry] {
        let listed = sections.flatMap(\.rows).map { row in
            switch row {
            case .page(let page, _): entry(page, title: page.title)
            case .machine(let machine): entry(.machine(machine.id), title: machine.name)
            }
        }
        return listed + [entry(.crew, title: SidebarPlan.machinesHeader), entry(.mochi, title: "Mochi")]
    }

    private static func entry(_ page: SidebarSelection, title: String) -> PaletteEntry {
        PaletteEntry(
            id: page.rawValue, title: title, symbol: page.symbol,
            shortcut: page.goKey.map { "⌘" + String($0.character) }, action: .go(page))
    }

    private static func actions(capture: CaptureMode, isRecording: Bool) -> [PaletteEntry] {
        [
            capture == .paused
                ? PaletteEntry(id: "resume", title: "Resume capture", symbol: "play", action: .resumeCapture)
                : PaletteEntry(
                    id: "pause", title: "Pause capture for 1 hour", symbol: "pause", action: .pauseCapture),
            PaletteEntry(
                id: "private", title: capture == .privateHour ? "Turn off private mode" : "Turn on private mode",
                symbol: "eye.slash", action: .privateMode(on: capture != .privateHour)),
            isRecording
                ? PaletteEntry(id: "stop-call", title: "Stop recording", symbol: "stop.circle", action: .stopCall)
                : PaletteEntry(id: "record", title: "Record a call…", symbol: "record.circle", action: .chooseCall),
            PaletteEntry(id: "settings", title: "Settings", symbol: "gearshape", shortcut: "⌘,", action: .settings),
        ]
    }

    /// The second step of "Record a call…": each app that plays sound, and the microphone alone.
    static func callChoices(apps: [(id: String, name: String)]) -> [PaletteEntry] {
        apps.map { PaletteEntry(id: "call-\($0.id)", title: $0.name, symbol: "app", action: .startCall(appID: $0.id)) }
            + [
                PaletteEntry(
                    id: "call-room", title: "In person (microphone only)", symbol: "mic", action: .startCall(appID: nil))
            ]
    }

    static func facts(_ facts: [TitledItem]) -> [PaletteEntry] {
        facts.compactMap { fact in
            guard let id = fact.item.id else { return nil }
            let detail = [fact.item["person"], fact.item["project"]].filter { !$0.isEmpty }.joined(separator: " · ")
            return PaletteEntry(
                id: "fact-\(id)", title: fact.title, detail: detail.isEmpty ? nil : detail, symbol: "text.quote",
                action: .openFact(id), words: fact.item.quote + " " + detail)
        }
    }
}
