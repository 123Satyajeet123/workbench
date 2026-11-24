import Foundation
import WorkbenchCore

struct UsageReport {
    struct Row: Identifiable {
        var name: String
        var usage = Usage()
        var calls = 0
        var id: String { name }
    }

    struct Day: Identifiable {
        var day: Date
        var usage = Usage()
        var id: Date { day }
    }

    let total: Usage
    let runs: [Run]
    var calls: Int { runs.count }
    let byModel: [Row]
    let byMachine: [Row]
    let byDay: [Day]

    init(runs: [Run], days: Int, now: Date, calendar: Calendar = .current, name: (String) -> String) {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
        let chosen = runs.filter { [.done, .failed].contains($0.outcome) && $0.startedAt >= first }
        total = chosen.compactMap(\.usage).reduce(Usage(), +)
        self.runs = chosen
        byModel = Self.rows(chosen) { Self.modelName($0.model) }
        byMachine = Self.rows(chosen) { name($0.task) }
        var perDay = Dictionary(grouping: chosen) { calendar.startOfDay(for: $0.startedAt) }
        byDay = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first).map { day in
                Day(day: day, usage: (perDay.removeValue(forKey: day) ?? []).compactMap(\.usage).reduce(Usage(), +))
            }
        }
    }

    static func modelName(_ raw: String) -> String {
        let parts = raw.split { $0 == "-" || $0 == " " }.map(String.init)
        guard parts.first == "claude" else { return raw }
        let rest = parts.dropFirst()
        let words = rest.filter { !$0.allSatisfy(\.isNumber) }.map(\.capitalized)
        let version = rest.filter { $0.allSatisfy(\.isNumber) && $0.count <= 2 }.joined(separator: ".")
        return (["Claude"] + words + (version.isEmpty ? [] : [version])).joined(separator: " ")
    }

    private static func rows(_ runs: [Run], by key: (Run) -> String) -> [Row] {
        Dictionary(grouping: runs, by: key).map { name, runs in
            Row(name: name, usage: runs.compactMap(\.usage).reduce(Usage(), +), calls: runs.count)
        }
        .sorted { ($0.usage.costUSD, $0.usage.tokens, $1.name) > ($1.usage.costUSD, $1.usage.tokens, $0.name) }
    }
}

extension Usage {
    var tokensWithoutCacheReads: Int { inputTokens + cacheWriteTokens + outputTokens }
}

extension Crew {
    func usageName(ofTask task: String) -> String {
        let named = name(ofTask: task)
        guard named == task else { return named }
        switch task.split(separator: ".").first {
        case "mochi": return "Mochi"
        case "memory": return "Memory"
        case "vc", "claims": return "Deal checks"
        case "draft": return "Drafts"
        case "machine": return "Brief improvements"
        case "usage": return "Plan checks"
        case "call": return "Echo"
        default: return task
        }
    }
}
