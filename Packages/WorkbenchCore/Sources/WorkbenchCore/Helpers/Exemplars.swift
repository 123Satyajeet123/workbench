import Foundation

public enum Exemplars {
    public static func pick(_ marked: [Item], for day: WorkDay, count: Int) -> [Item] {
        guard count > 0 else { return [] }
        let allowed = marked.filter { $0.day != day && EvalSplit($0.day) == .dev && $0.state != .proposed }
            .sorted { ($0.day, $0.start) > ($1.day, $1.start) }
        let wrong = Array(allowed.filter { $0.state == .rejected }.prefix(count / 2))
        let right = Array(allowed.filter { $0.state == .confirmed }.prefix(count - wrong.count))
        return right + wrong
    }
}
