import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

/// Everything the model and the code make from the line that holds the canary, through the writers of the app.
extension Scene {
    func readAndDerive() async throws {
        let folder = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Folder Example")
        let machine = try store.createMachine(from: .team, name: "Team Example", in: folder.id)
        self.folder = folder
        self.machine = machine
        let lines = try store.queries.currentLines(in: [Self.chatA], from: .distantPast, to: .distantFuture)
        let evidence = EvidenceSet(
            lines: lines.map {
                Evidence(
                    id: $0.number, start: $0.time ?? old, line: "\($0.actor ?? ""): \($0.text)", quotable: [$0.text],
                    lineID: $0.lineID, provenance: $0.provenance, consent: Consent(kind: .whatsapp, label: Self.chatA))
            }, context: ["members": ["Asha Example", "Ravi Example"]])
        let canaryNumber = try number(of: words.canary, in: lines)
        let sameChatNumber = try number(of: words.sameChat, in: lines)
        let reply = ScriptedReply.reply([
            ScriptedReply.item(
                text: "Send \(words.canary) to Ravi", cite: canaryNumber, quote: "send \(words.canary) to Ravi"),
            ScriptedReply.item(
                text: "Invoice \(words.sameChat) paid", cite: sameChatNumber, quote: "invoice \(words.sameChat) is paid"
            ),
            ScriptedReply.item(text: "Refused", cite: canaryNumber, quote: "\(words.canary) is not in the line"),
        ])
        try await read(evidence, reply: reply, machine: machine)
        try deriveFromItems(machine: machine, folder: folder)
    }

    private func number(of word: String, in lines: [StoredLine]) throws -> Int {
        guard let line = lines.first(where: { $0.text.contains(word) }) else {
            throw SceneError("no line holds \(word)")
        }
        return Int(line.number)
    }

    private func read(_ evidence: EvidenceSet, reply: String, machine: Machine) async throws {
        let reader = HelperReader(spec: machine.spec, model: RecordedModel(ScriptedModel([reply]), store: store))
        let day = WorkDay(containing: old)
        var run: RunID = 0
        _ = try await reader.readDay(day: day, scope: Self.chatA, evidence: evidence) { part in
            run = part.run ?? run
            try store.saveReading(
                part, of: machine.spec, day: day, scope: Self.chatA, grant: try grant(.whatsapp, Self.chatA))
        }
        made.run = run
        made.items = try store.queries.items(of: machine.spec.task, day: day, scope: Self.chatA).compactMap(\.id)
    }

    private func deriveFromItems(machine: Machine, folder: WorkObject) throws {
        guard let fact = made.items.first else { throw SceneError("the reading made no fact") }
        try store.mark(item: fact, as: .confirmed)
        let home = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Home Example")
        try store.moveHome(of: fact, into: home.id, surface: .machinePage)
        made.home = home.id
        try saveSummary(of: fact)
        try savePageProposal(machine: machine, fact: fact)
        try saveMochiProposal()
    }

    private func saveSummary(of fact: Int64) throws {
        let summary = Summary(
            scope: "person: Asha Example",
            short: Summary.Line(text: "Asha Example sent \(words.canary).", cites: [fact]), details: [], run: made.run)
        try store.saveSummaries(
            [StoredSummary(fingerprint: "f", kinds: [.whatsapp], summary: summary)], day: WorkDay(containing: old),
            task: machine?.spec.task ?? "", field: "person")
    }

    private func savePageProposal(machine: Machine, fact: Int64) throws {
        let facts = try store.queries.items(ids: [fact])
        let run = try store.beginRun(
            task: PageComposer.task, model: "scripted", prompt: "by hand", input: "no model call", kinds: [.whatsapp],
            window: [WindowLine(number: 1, lineID: made.canaryLine)])
        try store.finishRun(run, model: "scripted", usage: Usage(), reply: "")
        let sentence = CitedText(text: "Asha Example waits on \(words.canary).", cites: [.fact(fact)])
        let (page, verdicts) = PageGate(catalog: PageCatalog(spec: machine.spec, items: facts)).apply(
            [.insert(.text(sentence), after: nil)], to: MachinePage())
        guard let pageObject = machine.page else { throw SceneError("the machine has no page") }
        made.page = try store.propose(
            PageProposal(note: "A note on \(words.canary).", verdicts: verdicts, page: page, run: run), on: pageObject,
            by: machine.id, request: "Show the follow-ups", owner: owner)
    }

    private func saveMochiProposal() throws {
        let run = try store.beginRun(
            task: "mochi", model: "scripted", prompt: "none", input: "x", kinds: [.whatsapp],
            window: [WindowLine(number: 1, lineID: made.canaryLine)])
        try store.saveProposals(
            Mochi.Result(
                proposals: [
                    Proposal(
                        run: run, name: "Name", template: "t", brief: "brief", why: "because of \(words.canary)",
                        view: "table", evidence: [1, 2, 3], decision: .waiting)
                ], dropped: 0, run: run), grant: try grant(.screen, nil))
    }

    /// The copies a store makes of itself: a daily snapshot, and the copy a migration makes first.
    func makeBackups() throws {
        try store.snapshotIfDue()
        try store.backups.prepare()
        try store.backups.writeCopy(of: store.writer, as: store.backups.preMigrationCopy)
    }
}
