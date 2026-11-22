import Foundation
import WorkbenchCore

struct StripMachine: Equatable {
    var machine: Machine
    var watch: WatchSchedule
    var rule: String?
}

struct DealDigest: Equatable {
    var triage: Triage?
    var action: Item?
    var story: DealStory
    var machines: [StripMachine]
}

struct DealDigestReader {
    let store: Store
    let me: String

    func digest(of deal: WorkObject, machines: [Machine], actions: [Item]) throws -> DealDigest {
        let own = actions.filter { $0[DealAction.dealField] == deal.id }
        var ratings: [String: Rating] = [:]
        var marks: [String: [DealStory.Marked]] = [:]
        var touching: [StripMachine] = []
        var first: Triage?
        for (event, linked) in deal.items {
            marks[event.id] = try linkedMarks(of: event, linked)
            guard
                let machine = machines.first(where: { $0.task == linked.task })
                    ?? machines.first(where: { $0.name == linked.machine })
            else { continue }
            let triage = machine.spec.criteria?.triage(linked.fields)
            triage.map { ratings[event.id] = $0.rating }
            first = first ?? triage
            if !touching.contains(where: { $0.machine == machine }) {
                touching.append(try stripMachine(machine, triage: triage))
            }
        }
        if !own.isEmpty {
            touching += try machines.filter { $0.template == HelperSpec.derailment.task }.map { try stripMachine($0) }
        }
        return DealDigest(
            triage: first, action: own.first { $0.isOpen(in: DealAction.lifecycle, at: store.clock()) },
            story: DealStory.make(deal: deal, ratings: ratings, marks: marks, actions: own), machines: touching)
    }

    private func linkedMarks(of event: WorkEvent, _ linked: LinkedItem) throws -> [DealStory.Marked] {
        if event.author == me, let id = linked.itemID { return try store.queries.marks(ofItem: id) }
        return linked.state == .proposed ? [] : [.init(state: linked.state, at: event.at)]
    }

    private func stripMachine(_ machine: Machine, triage: Triage? = nil) throws -> StripMachine {
        let decided = triage?.decidedBy.compactMap { machine.spec.criteria?.rule($0)?.summary } ?? []
        let rule = triage.map { call in
            decided.isEmpty
                ? "Rated \(call.rating.rawValue): no rule pushed it either way"
                : "Rated \(call.rating.rawValue) by: \(decided.joined(separator: "; "))"
        }
        return StripMachine(
            machine: machine, watch: try MachineKey.watch(machine.task).load(from: store) ?? WatchSchedule(), rule: rule
        )
    }
}
