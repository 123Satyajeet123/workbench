import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// The team folder the team syncs (iCloud Drive, Syncthing). Everything in it is a signed, encrypted envelope: the
/// folder holds no plaintext, and a person reads only what was sealed for them. A shared machine holds a spec and its
/// record in counts; adopting one makes it the founder's own, starting at zero trust. A shared day holds one machine's
/// items of a day, and goes only to teammates who could already read the items' source. The public folder stays
/// plain: anyone may read it.
@Observable
final class TeamCatalogModel {
    struct Refusal: Equatable {
        let task: String
        let missing: [Team.Person]
        /// Empty when no link can widen the audience, as for the founder's own screen.
        let group: [WhatsAppMember]
    }

    /// Where a machine is shared: the team's folder, or a public one anyone may read (such as a clone of a public git
    /// repository; pushing it is the person's own act).
    enum Place: Hashable {
        case team, everyone
    }

    private static let folderKey = "team.folder"
    private static let publicKey = "catalog.public"

    private(set) var folder: URL?
    private(set) var publicFolder: URL?
    private(set) var shared: [SharedMachine] = []
    private(set) var published: [SharedMachine] = []
    private(set) var reviews: [Place: [MachineReview]] = [:]
    private(set) var days: [SharedDay] = []
    /// Every work event the team folder holds that this person may read.
    private(set) var workEvents: [WorkEvent] = []
    private(set) var unreadable: [String] = []
    private(set) var refusal: Refusal?
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    let trust: TeamTrustModel
    @ObservationIgnored let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let author: () -> String

    init(store: Store, crew: Crew, author: @escaping () -> String, secrets: SecretStore = KeychainSecrets()) {
        self.store = store
        self.crew = crew
        self.author = author
        trust = TeamTrustModel(store: store, secrets: secrets)
        folder = ((try? store.queries.state(forKey: Self.folderKey)) ?? nil).map { URL(filePath: $0) }
        publicFolder = ((try? store.queries.state(forKey: Self.publicKey)) ?? nil).map { URL(filePath: $0) }
        refresh()
    }

    var me: String { author().cleaned ?? "Me" }
    var teammates: [SharedMachine] { shared.filter { $0.author != me } }
    /// Days teammates shared with this person. The receiving side checks the audience again.
    var teammatesDays: [SharedDay] { days.filter { $0.author != me && $0.isVisible(to: me) } }

    var publicMachines: [SharedMachine] { published.filter { $0.author != me } }

    func folder(for place: Place) -> URL? { place == .team ? folder : publicFolder }
    private func machines(in place: Place) -> [SharedMachine] { place == .team ? shared : published }

    func isShared(_ helper: HelperModel, in place: Place = .team) -> Bool {
        machines(in: place).contains { $0.author == me && $0.spec.task == helper.spec.task }
    }

    func review(_ machine: SharedMachine, in place: Place, approve: Bool, note: String) {
        guard machine.author != me else { return }
        problems.attempt("save the review") {
            let review = MachineReview(reviewer: me, of: machine, approve: approve, note: note, at: store.clock())
            if place == .team {
                try send([.review(review)])
            } else if let folder = folder(for: place) {
                try review.write(to: folder)
            }
        }
        refresh()
    }

    func choosePublic(_ url: URL) {
        problems.attempt("save the public folder") {
            try store.saveState(url.path(percentEncoded: false), forKey: Self.publicKey)
        }
        publicFolder = url
        refresh()
    }

    func choose(_ url: URL) {
        problems.attempt("save the team folder") {
            try store.saveState(url.path(percentEncoded: false), forKey: Self.folderKey)
        }
        folder = url
        refresh()
    }

    func refresh() {
        unreadable = []
        if let folder { problems.attempt("read the team folder") { try readTeam(folder) } }
        if let publicFolder {
            let machines = SharedMachine.read(from: publicFolder)
            let reviews = MachineReview.read(from: publicFolder)
            (published, self.reviews[.everyone]) = (machines.files, reviews.files)
            unreadable += (machines.unreadable + reviews.unreadable.map { "reviews/\($0)" }).map { "public/\($0)" }
        }
    }

    /// Reads every letter in the team folder and keeps what passes the checks.
    private func readTeam(_ folder: URL) throws {
        try trust.announce(folder: folder, me: me)
        guard let sync = trust.sync(folder: folder, me: me) else {
            trust.scan(folder: folder)
            (shared, days, workEvents, reviews[.team]) = ([], [], [], [])
            return
        }
        let received = try sync.receive()
        trust.absorb(received)
        (shared, days, workEvents, reviews[.team]) = (
            received.machines, received.days, received.events, received.reviews
        )
    }

    /// Seals things for their audiences and puts them in the team folder. Returns how many were kept on this Mac
    /// because a reader has no confirmed key.
    @discardableResult
    func send(_ things: [SharedThing]) throws -> Int {
        guard let sync else { throw SyncError.notAMember }
        return try sync.publish(things).held
    }

    /// The team sync for the chosen folder, once a founder is known.
    var sync: TeamSync? { folder.flatMap { trust.sync(folder: $0, me: me) } }

    func isShared(day helper: HelperModel) -> Bool {
        days.contains { $0.author == me && $0.task == helper.spec.task && $0.day == helper.day.description }
    }

    /// Shares the machine's items of the shown day, when every teammate can already read their source. Otherwise it
    /// holds the share back and names who cannot.
    func share(day helper: HelperModel) async {
        guard folder != nil else {
            problems.show("Choose a team folder in Settings › Team first.")
            return
        }
        await problems.attempt("share \(helper.name)'s day") {
            let (recipients, missing) = try await audience(of: helper)
            guard !recipients.isEmpty else {
                problems.show("Add your teammates in Settings › Team first.")
                return
            }
            guard missing.isEmpty else { return }
            let day = SharedDay(
                author: me, machine: helper.machine, day: helper.day, items: helper.items,
                audience: [me] + recipients.map(\.name), at: store.clock())
            guard try send([.day(day)]) == 0 else {
                problems.show(
                    "A teammate has no confirmed key yet, so nothing was sent. Confirm their fingerprint first.")
                return
            }
            try store.log(
                "share_day", target: helper.spec.task,
                detail: [
                    "day": day.day, "to": recipients.map(\.name).joined(separator: ", "),
                    "items": String(day.entries.count),
                ])
        }
        refresh()
    }

    func unshare(day helper: HelperModel) {
        problems.attempt("stop sharing \(helper.name)'s day") {
            let day = SharedDay.key(author: me, task: helper.spec.task, day: helper.day.description)
            try send([.retraction(key: day, by: me)])
            try store.log("unshare_day", target: helper.spec.task, detail: ["day": helper.day.description])
        }
        refresh()
    }

    /// The founder says which group member a teammate is; the held-back share is checked again, not sent.
    func link(_ person: Team.Person, to member: WhatsAppMember, for helper: HelperModel) async {
        await problems.attempt("link \(person.name)") {
            try store.link(person, whatsapp: member.jid)
            _ = try await audience(of: helper)
        }
    }

    /// The teammates a share would go to, and those among them who cannot read the source. Sets the refusal.
    private func audience(of helper: HelperModel) async throws -> (recipients: [Team.Person], missing: [Team.Person]) {
        let found = try await readers(of: helper)
        refusal =
            found.missing.isEmpty ? nil : Refusal(task: helper.spec.task, missing: found.missing, group: found.group)
        return (found.recipients, found.missing)
    }

    /// Writes the machine's spec and its record in counts, never what it read, to the team or the public folder.
    func share(_ helper: HelperModel, to place: Place = .team) {
        guard let folder = folder(for: place) else {
            problems.show(
                place == .team
                    ? "Choose a team folder in Settings › Team first."
                    : "Choose a public folder on the Team page first.")
            return
        }
        problems.attempt("share \(helper.name)") {
            let record = SharedMachine.Record(task: helper.spec.task, quality: try store.queries.quality())
            let machine = SharedMachine(author: me, machine: helper.machine, record: record, at: store.clock())
            if place == .team { try send([.machine(machine)]) } else { try machine.write(to: folder) }
        }
        refresh()
    }

    func unshare(_ helper: HelperModel, from place: Place = .team) {
        guard let folder = folder(for: place) else { return }
        problems.attempt("stop sharing \(helper.name)") {
            if place == .team {
                try send([.retraction(key: SharedMachine.key(author: me, task: helper.spec.task), by: me)])
            } else {
                try SharedMachine.remove(author: me, parts: [helper.spec.task], from: folder)
            }
        }
        refresh()
    }

    /// The teammate's machine becomes the founder's own: the same spec (brief, fields, view), a new task, zero trust.
    @discardableResult
    func adopt(_ machine: SharedMachine) -> Int64? {
        guard MachineTemplate.of(id: machine.template) != nil else {
            problems.show("\(machine.author)'s \(machine.name) needs a template this version does not have.")
            return nil
        }
        return crew.create(spec: machine.spec, template: machine.template, name: machine.name)
    }

    func dismissRefusal() { refusal = nil }

}
