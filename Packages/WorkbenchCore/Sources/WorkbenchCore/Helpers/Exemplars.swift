import Foundation

/// Which of the founder's marks a machine sees as examples (research 20 §9.2). Leave one day out: never an item of the
/// day being read, never an item of a held-out or trial day (those judge versions and never shape them), never an unmarked
/// item. Newest days first; at most half of them wrong, so the machine sees mistakes without learning only refusal.
public enum Exemplars {
    public static func pick(_ marked: [Item], for day: WorkDay, count: Int) -> [Item] {
        guard count > 0 else { return [] }
        let allowed = marked.filter { $0.day != day && DevHalf($0.day) == .learn && $0.state != .proposed }
            .sorted { ($0.day, $0.start) > ($1.day, $1.start) }
        let wrong = Array(allowed.filter { $0.state == .rejected }.prefix(count / 2))
        let right = Array(allowed.filter { $0.state == .confirmed }.prefix(count - wrong.count))
        return right + wrong
    }
}
