import WorkbenchCore

/// What a machine is doing, as the sidebar's dot shows it.
enum MachineStatus: Equatable {
    case reading, needsYou, idle

    init(isReading: Bool, needsYou: Bool) {
        self = isReading ? .reading : (needsYou ? .needsYou : .idle)
    }

    var words: String {
        switch self {
        case .reading: "reading"
        case .needsYou: "needs you"
        case .idle: "idle"
        }
    }
}

struct SidebarMachine: Equatable, Identifiable {
    let id: Int64
    let name: String
    let status: MachineStatus
}

enum SidebarRow: Equatable, Identifiable {
    case page(SidebarSelection, count: Int)
    case machine(SidebarMachine)

    var selection: SidebarSelection {
        switch self {
        case .page(let page, _): page
        case .machine(let machine): .machine(machine.id)
        }
    }

    var id: String { selection.rawValue }
}

struct SidebarSection: Equatable, Identifiable {
    let header: String?
    let rows: [SidebarRow]

    var id: String { header ?? rows.first?.id ?? "" }
}

/// The sidebar's rows, top to bottom. The order is fixed: only the machines and the Deals row change with the team.
enum SidebarPlan {
    static let machinesHeader = "Machines"
    private static let dealType = ObjectTypes.deal.id

    static func sections(template: TeamTemplate, machines: [SidebarMachine], today: Int, checks: Int)
        -> [SidebarSection]
    {
        var places: [SidebarRow] = [
            .page(.day, count: today), .page(.review, count: checks), .page(.people, count: 0),
            .page(.projects, count: 0), .page(.calls, count: 0),
        ]
        if template.objectTypes.contains(where: { $0.id == dealType }) { places.append(.page(.deals, count: 0)) }
        return [
            SidebarSection(header: nil, rows: places),
            SidebarSection(header: machinesHeader, rows: machines.map(SidebarRow.machine)),
            SidebarSection(header: nil, rows: [.page(.catalog, count: 0)]),
        ]
    }

    /// Pages that have no row: Mochi and the Crew page open from the Machines header, the Crew page and ⌘K.
    private static let reachedWithoutRow: [SidebarSelection] = [.mochi, .crew]

    /// The page to show for a saved or requested one. A page the sidebar no longer lists, such as Deals on another
    /// team or a deleted machine, gives way to Today.
    static func landing(_ selection: SidebarSelection, in sections: [SidebarSection]) -> SidebarSelection {
        let listed = sections.flatMap(\.rows).contains { $0.selection == selection }
        return listed || reachedWithoutRow.contains(selection) ? selection : .day
    }
}
