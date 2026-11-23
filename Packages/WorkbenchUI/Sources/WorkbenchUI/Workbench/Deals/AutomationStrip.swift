import Foundation
import WorkbenchCore

struct AutomationRow: Equatable, Identifiable {
    var id: Int64
    var name: String
    var role: String
    var lastRun: String
    var nextRun: String
    var precision: String
    var rule: String?
}

/// The rows of a deal's automation strip. Counts and events only: it calls no model.
enum AutomationStrip {
    static func rows(for digest: DealDigest, runs: [Run], quality: [Quality], now: Date) -> [AutomationRow] {
        digest.machines.map { touching in
            let machine = touching.machine
            let facts = CrewCardFacts(task: machine.task, runs: runs, quality: quality, now: now)
            let lastRead = runs.filter { $0.task == machine.task && $0.outcome == .done }.map(\.startedAt).max()
            return AutomationRow(
                id: machine.id, name: machine.name, role: role(of: machine), lastRun: facts.lastReading,
                nextRun: nextRun(touching.watch.nextRun(after: lastRead, now: now), now: now), precision: facts.health,
                rule: touching.rule)
        }
    }

    private static func role(of machine: Machine) -> String {
        machine.template == HelperSpec.derailment.task ? "Watches the action" : "Reads and rates"
    }

    private static func nextRun(_ date: Date?, now: Date) -> String {
        guard let date else { return "Reads when you press Read" }
        return
            "Next read \(date.formatted(date: Calendar.current.isDate(date, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened))"
    }
}
