import Foundation
import Observation
import WorkbenchCore

/// The team's shared machines in a folder the team syncs (iCloud Drive, Syncthing). Each person writes only their own
/// files; a file holds a machine's spec and its record in counts, never what it read. Adopting a teammate's machine
/// makes it the founder's own, starting at zero trust.
@Observable
final class TeamCatalogModel {
    private static let folderKey = "team.folder"

    private(set) var folder: URL?
    private(set) var shared: [SharedMachine] = []
    private(set) var unreadable: [String] = []
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let author: () -> String

    init(store: Store, crew: Crew, author: @escaping () -> String) {
        self.store = store
        self.crew = crew
        self.author = author
        folder = ((try? store.queries.state(forKey: Self.folderKey)) ?? nil).map { URL(filePath: $0) }
        refresh()
    }

    var me: String { author().cleaned ?? "Me" }
    var teammates: [SharedMachine] { shared.filter { $0.author != me } }

    func isShared(_ helper: HelperModel) -> Bool {
        shared.contains { $0.author == me && $0.spec.task == helper.spec.task }
    }

    func choose(_ url: URL) {
        attempt("save the team folder") { try store.saveState(url.path(percentEncoded: false), forKey: Self.folderKey) }
        folder = url
        refresh()
    }

    func refresh() {
        guard let folder else { return }
        (shared, unreadable) = SharedMachine.read(from: folder)
    }

    /// Writes the machine's spec and its record in counts to the team folder.
    func share(_ helper: HelperModel) {
        guard let folder else {
            problem = "Choose a team folder in Settings › Team first."
            return
        }
        attempt("share \(helper.name)") {
            let record = SharedMachine.Record(task: helper.spec.task, quality: try store.queries.quality())
            try SharedMachine(author: me, machine: helper.machine, record: record, at: store.clock()).write(to: folder)
        }
        refresh()
    }

    func unshare(_ helper: HelperModel) {
        guard let folder else { return }
        attempt("stop sharing \(helper.name)") {
            try SharedMachine.remove(author: me, task: helper.spec.task, from: folder)
        }
        refresh()
    }

    /// The teammate's machine becomes the founder's own, from the same template with the same brief.
    @discardableResult
    func adopt(_ machine: SharedMachine) -> Int64? {
        guard let template = MachineTemplate.all.first(where: { $0.spec.task == machine.template }),
            let id = crew.create(from: template, name: machine.name), let helper = crew.helper(id: id)
        else {
            problem = "\(machine.author)'s \(machine.name) needs a template this version does not have."
            return nil
        }
        crew.edit(helper, brief: machine.spec.brief)
        return id
    }

    func dismissProblem() { problem = nil }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}
