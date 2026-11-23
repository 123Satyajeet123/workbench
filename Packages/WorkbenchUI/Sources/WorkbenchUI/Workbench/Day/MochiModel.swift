import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// Mochi as the master helper: reads the timeline of past training days, proposes machines for work that repeats, and
/// builds the ones the founder accepts. Held-out days are never read here, so they stay fit to judge a machine later.
@Observable
final class MochiModel {
    static let days = 14

    private(set) var proposals: [Proposal] = []
    private(set) var trainingDays = 0
    private(set) var phase = ReadPhase.idle
    private(set) var problem: String?
    private(set) var brief: MorningBrief?
    private(set) var briefPhase = ReadPhase.idle
    private static let briefKey = StateKey<MorningBrief>.json("mochi.brief")

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel

    init(store: Store, crew: Crew, makeModel: ((ModelChoice) -> RecordedModel)? = nil) {
        self.store = store
        self.crew = crew
        self.makeModel = makeModel ?? { $0.model(store: store) }
        refresh()
    }

    var waiting: [Proposal] { proposals.filter { $0.decision == .waiting } }
    var canDiscover: Bool { trainingDays >= Mochi.minimumDays && phase != .reading }

    /// Accepted over decided: how often Mochi's proposals are worth building.
    var acceptance: (accepted: Int, decided: Int) {
        let decided = proposals.filter { $0.decision == .accepted || $0.decision == .rejected }
        return (decided.filter { $0.decision == .accepted }.count, decided.count)
    }

    func refresh() {
        do {
            proposals = try store.queries.proposals()
            trainingDays = Mochi.days(in: try blocks())
            brief = try Self.briefKey.load(from: store)
        } catch {
            problem = "Could not read Mochi's proposals: \(error.localizedDescription)"
        }
    }

    /// Writes the brief of `day` from every machine's items that day. Nil when the day had none: no call is made.
    @discardableResult
    func writeBrief(for day: WorkDay) async -> MorningBrief? {
        let sources = crew.machines.flatMap { helper in
            helper.items(on: day).map {
                Briefer.Source(machine: helper.name, fields: helper.spec.fields.map(\.name), item: $0)
            }
        }
        briefPhase = .reading
        defer { briefPhase = .idle }
        do {
            let briefer = Briefer(model: makeModel(try ModelChoice.saved(in: store)))
            let unseen = crew.machines.filter { !$0.isPaused && $0.items(on: day).isEmpty }.map(\.name)
            guard let written = try await briefer.brief(sources, day: day, unseen: unseen) else {
                problem = "No machine found anything on \(day) to brief."
                return nil
            }
            try Self.briefKey.save(written, to: store)
            brief = written
            problem = nil
            return written
        } catch {
            problem = "Mochi could not write the brief: \(error.localizedDescription)"
            return nil
        }
    }

    func evidence(_ proposal: Proposal) -> [Item] {
        let cited = Set(proposal.evidence)
        return ((try? blocks()) ?? []).filter { $0.id.map(cited.contains) == true }
    }

    func discover() async {
        guard canDiscover else { return }
        phase = .reading
        do {
            _ = try await store.grant(for: .screen, at: store.clock())
            let mochi = Mochi(model: makeModel(try ModelChoice.saved(in: store)))
            let result = try await mochi.propose(
                blocks: try blocks(), roster: crew.machines.map(\.machine),
                templates: MachineTemplate.all.map {
                    Mochi.Template(id: $0.spec.task, does: $0.detail, views: Array($0.spec.views.keys))
                },
                earlier: proposals)
            try store.saveProposals(result, grant: try await store.grant(for: .screen, at: store.clock()))
            phase = .read(kept: result.proposals.count, dropped: result.dropped)
            problem = nil
        } catch {
            phase = .idle
            problem = "Mochi could not read your days: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Builds the machine from its template with Mochi's brief, then records the decision.
    @discardableResult
    func accept(_ proposal: Proposal) -> Int64? {
        guard let template = MachineTemplate.all.first(where: { $0.spec.task == proposal.template }),
            let id = crew.create(from: template, name: proposal.name), let helper = crew.helper(id: id)
        else {
            problem = "Mochi's proposal names a template this version does not have."
            return nil
        }
        crew.edit(helper, brief: proposal.brief)
        crew.show(helper, as: proposal.view)
        decide(proposal, .accepted)
        return id
    }

    func decide(_ proposal: Proposal, _ decision: Proposal.Decision) {
        guard let id = proposal.id else { return }
        do {
            try store.decide(id, decision)
        } catch {
            problem = "Could not save the decision: \(error.localizedDescription)"
        }
        refresh()
    }

    func dismissProblem() { problem = nil }

    private func blocks() throws -> [Item] {
        guard let timeline = crew.timeline else { return [] }
        let since = WorkDay(containing: store.clock()).adding(days: -Self.days)
        return try store.queries.items(of: timeline.spec.task, since: since).filter { EvalSplit($0.day) == .dev }
    }
}
