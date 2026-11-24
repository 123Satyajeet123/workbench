import Foundation
import WorkbenchCore

struct CrewCardFacts: Equatable {
    var lastReading: String
    var health: String
    var costThisWeek: String

    init(task: String, runs: [Run], quality: [Quality], now: Date) {
        let own = runs.filter { Trial.machineTask(of: $0.task) == task }
        lastReading = Self.lastReading(own.filter { $0.task == task && $0.outcome == .done })
        health = Self.health(quality.first { $0.task == task })
        costThisWeek = Self.cost(own.filter { $0.startedAt >= now.addingTimeInterval(-7 * 86_400) })
    }

    private static func lastReading(_ readings: [Run]) -> String {
        guard let last = readings.max(by: { $0.startedAt < $1.startedAt }) else { return "Has not read yet" }
        let when = last.startedAt.formatted(date: .abbreviated, time: .shortened)
        return last.kept.map { "Last read \(when), kept \($0)" } ?? "Last read \(when)"
    }

    private static func health(_ row: Quality?) -> String {
        health(
            right: row?.all.confirmed ?? 0, of: row?.all.marked ?? 0,
            trust: row?.heldOutAudit.status ?? Certificate().status)
    }

    /// How right the machine was by the founder's marks, and how far it is from trust. No right depends on trust yet.
    static func health(right: Int, of marked: Int, trust: Certificate.Status) -> String {
        let trusted =
            switch trust {
            case .earned: TrustWording.earned
            case .needsMore(let more): "needs \(more) more \(more == 1 ? "check" : "checks") before it is trusted"
            }
        guard marked > 0 else { return trusted.prefix(1).uppercased() + trusted.dropFirst() }
        return "Right \(right) of \(marked) you checked; \(trusted)"
    }

    private static func cost(_ runs: [Run]) -> String {
        let usage = runs.compactMap(\.usage).reduce(Usage(), +)
        return usage.costUSD == 0 ? "No cost this week" : "\(usage.costText) this week"
    }
}
