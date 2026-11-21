import Foundation

/// Moves a person's own plaintext files out of the team folder: they are read once, sent as envelopes, and removed.
/// Other people's files are never read: each person's app moves its own. A file stays when a reader of it still has
/// no confirmed key, so nothing is lost; the next run tries again.
public enum PlaintextMigration {
    /// The number of things sent. Files that were sent in full are removed.
    @discardableResult
    public static func run(team: URL, sync: TeamSync) throws -> Int {
        let name = sync.name
        let events = WorkLog.read(from: team).events.filter { $0.author == name }
        let days = SharedDay.read(from: team).files.filter { $0.author == name }
        let machines = SharedMachine.read(from: team).files.filter { $0.author == name }
        let reviews = MachineReview.read(from: team).files.filter { $0.reviewer == name }
        let things: [SharedThing] =
            events.map(SharedThing.event) + days.map(SharedThing.day) + machines.map(SharedThing.machine)
            + reviews.map(SharedThing.review)
        guard !things.isEmpty else { return 0 }
        let outcome = try sync.publish(things)
        guard outcome.held == 0 else { return outcome.sent }
        try WorkLog.remove(author: name, from: team)
        for day in days { try SharedDay.remove(author: name, parts: day.fileParts, from: team) }
        for machine in machines { try SharedMachine.remove(author: name, parts: machine.fileParts, from: team) }
        for review in reviews { try MachineReview.remove(author: name, parts: review.fileParts, from: team) }
        return outcome.sent
    }
}
