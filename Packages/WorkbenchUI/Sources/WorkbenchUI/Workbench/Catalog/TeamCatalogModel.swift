import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// The team folder the team syncs (iCloud Drive, Syncthing). Each person writes only their own files. A machine file
/// holds a spec and its record in counts; adopting one makes it the founder's own, starting at zero trust. A day file
/// holds one machine's items of a day, and goes only to teammates who could already read the items' source.
@Observable
final class TeamCatalogModel {
    /// A share held back: the teammates who cannot read the source, and the group members they might be.
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
    private(set) var unreadable: [String] = []
    private(set) var refusal: Refusal?
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let author: () -> String

    init(store: Store, crew: Crew, author: @escaping () -> String) {
        self.store = store
        self.crew = crew
        self.author = author
        folder = ((try? store.queries.state(forKey: Self.folderKey)) ?? nil).map { URL(filePath: $0) }
        publicFolder = ((try? store.queries.state(forKey: Self.publicKey)) ?? nil).map { URL(filePath: $0) }
        refresh()
    }

    var me: String { author().cleaned ?? "Me" }
    var teammates: [SharedMachine] { shared.filter { $0.author != me } }
    /// Days teammates shared with this person. The receiving side checks the audience again.
    var teammatesDays: [SharedDay] { days.filter { $0.author != me && $0.isVisible(to: me) } }

    /// Other people's machines in the public folder.
    var publicMachines: [SharedMachine] { published.filter { $0.author != me } }

    func folder(for place: Place) -> URL? { place == .team ? folder : publicFolder }
    private func machines(in place: Place) -> [SharedMachine] { place == .team ? shared : published }

    func isShared(_ helper: HelperModel, in place: Place = .team) -> Bool {
        machines(in: place).contains { $0.author == me && $0.spec.task == helper.spec.task }
    }

    /// People other than its author who approved the version shared now.
    func approvers(of machine: SharedMachine, in place: Place) -> [String] {
        machine.approvers(in: reviews[place] ?? [])
    }

    /// This person's review of the shared version, if any.
    func myReview(of machine: SharedMachine, in place: Place) -> MachineReview? {
        (reviews[place] ?? []).first {
            $0.reviewer == me && $0.author == machine.author && $0.task == machine.spec.task
                && $0.version == machine.version
        }
    }

    func review(_ machine: SharedMachine, in place: Place, approve: Bool, note: String) {
        guard let folder = folder(for: place), machine.author != me else { return }
        attempt("save the review") {
            try MachineReview(reviewer: me, of: machine, approve: approve, note: note, at: store.clock()).write(
                to: folder)
        }
        refresh()
    }

    func choosePublic(_ url: URL) {
        attempt("save the public folder") {
            try store.saveState(url.path(percentEncoded: false), forKey: Self.publicKey)
        }
        publicFolder = url
        refresh()
    }

    func choose(_ url: URL) {
        attempt("save the team folder") { try store.saveState(url.path(percentEncoded: false), forKey: Self.folderKey) }
        folder = url
        refresh()
    }

    func refresh() {
        unreadable = []
        if let folder {
            let machines = SharedMachine.read(from: folder)
            let days = SharedDay.read(from: folder)
            let reviews = MachineReview.read(from: folder)
            (shared, self.days, self.reviews[.team]) = (machines.files, days.files, reviews.files)
            unreadable +=
                machines.unreadable + days.unreadable.map { "days/\($0)" }
                + reviews.unreadable.map { "reviews/\($0)" }
        }
        if let publicFolder {
            let machines = SharedMachine.read(from: publicFolder)
            let reviews = MachineReview.read(from: publicFolder)
            (published, self.reviews[.everyone]) = (machines.files, reviews.files)
            unreadable += (machines.unreadable + reviews.unreadable.map { "reviews/\($0)" }).map { "public/\($0)" }
        }
    }

    func isShared(day helper: HelperModel) -> Bool {
        days.contains { $0.author == me && $0.task == helper.spec.task && $0.day == helper.day.description }
    }

    /// Shares the machine's items of the shown day, when every teammate can already read their source. Otherwise it
    /// holds the share back and names who cannot.
    func share(day helper: HelperModel) async {
        guard let folder else {
            problem = "Choose a team folder in Settings › Team first."
            return
        }
        do {
            let (recipients, missing) = try await audience(of: helper)
            guard !recipients.isEmpty else {
                problem = "Add your teammates in Settings › Team first."
                return
            }
            guard missing.isEmpty else { return }
            let day = SharedDay(
                author: me, machine: helper.machine, day: helper.day, items: helper.items,
                audience: [me] + recipients.map(\.name), at: store.clock())
            try day.write(to: folder)
            try store.log(
                "share_day", target: helper.spec.task,
                detail: [
                    "day": day.day, "to": recipients.map(\.name).joined(separator: ", "),
                    "items": String(day.entries.count),
                ])
        } catch {
            problem = "Could not share \(helper.name)'s day: \(error.localizedDescription)"
        }
        refresh()
    }

    func unshare(day helper: HelperModel) {
        guard let folder else { return }
        attempt("stop sharing \(helper.name)'s day") {
            try SharedDay.remove(author: me, parts: [helper.spec.task, helper.day.description], from: folder)
            try store.log("unshare_day", target: helper.spec.task, detail: ["day": helper.day.description])
        }
        refresh()
    }

    /// The founder says which group member a teammate is; the held-back share is checked again, not sent.
    func link(_ person: Team.Person, to member: WhatsAppMember, for helper: HelperModel) async {
        do {
            try store.link(person, whatsapp: member.jid)
            _ = try await audience(of: helper)
        } catch {
            problem = "Could not link \(person.name): \(error.localizedDescription)"
        }
    }

    /// The teammates a share would go to, and those among them who cannot read the source. Sets the refusal.
    private func audience(of helper: HelperModel) async throws -> (recipients: [Team.Person], missing: [Team.Person]) {
        let found = try await readers(of: helper)
        refusal =
            found.missing.isEmpty ? nil : Refusal(task: helper.spec.task, missing: found.missing, group: found.group)
        return (found.recipients, found.missing)
    }

    /// Who can already read the machine's source, by the audience rule: a group's linked members; for the founder's
    /// screen and pages, nobody else.
    func readers(of helper: HelperModel) async throws -> (
        recipients: [Team.Person], missing: [Team.Person], group: [WhatsAppMember]
    ) {
        let recipients = (try store.queries.team()?.people ?? []).filter { !$0.isMe }
        var readers: Set<Int64> = []
        var group: [WhatsAppMember] = []
        if case .whatsapp(let source) = helper.source {
            try await source.loadMembers()
            group = source.members
            readers = Audience.readers(links: try store.queries.whatsappLinks(), group: Set(group.map(\.jid)))
        }
        return (recipients, Audience.missing(recipients: recipients, readers: readers), group)
    }

    /// Writes the machine's spec and its record in counts, never what it read, to the team or the public folder.
    func share(_ helper: HelperModel, to place: Place = .team) {
        guard let folder = folder(for: place) else {
            problem =
                place == .team
                ? "Choose a team folder in Settings › Team first." : "Choose a public folder on the Team page first."
            return
        }
        attempt("share \(helper.name)") {
            let record = SharedMachine.Record(task: helper.spec.task, quality: try store.queries.quality())
            try SharedMachine(author: me, machine: helper.machine, record: record, at: store.clock()).write(to: folder)
        }
        refresh()
    }

    func unshare(_ helper: HelperModel, from place: Place = .team) {
        guard let folder = folder(for: place) else { return }
        attempt("stop sharing \(helper.name)") {
            try SharedMachine.remove(author: me, parts: [helper.spec.task], from: folder)
        }
        refresh()
    }

    /// The teammate's machine becomes the founder's own: the same spec (brief, fields, view), a new task, zero trust.
    @discardableResult
    func adopt(_ machine: SharedMachine) -> Int64? {
        guard MachineTemplate.all.contains(where: { $0.spec.task == machine.template }) else {
            problem = "\(machine.author)'s \(machine.name) needs a template this version does not have."
            return nil
        }
        return crew.create(spec: machine.spec, template: machine.template, name: machine.name)
    }

    func dismissProblem() { problem = nil }
    func dismissRefusal() { refusal = nil }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}
