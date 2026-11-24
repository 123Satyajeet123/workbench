import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

/// A store with one erased chat and one kept chat, and a copy of the words of each in every kind of derived row the
/// writers make: facts, events, a summary, a page proposal and its block, a judge's product with claims, cites,
/// verdicts and a mark, one of Mochi's proposals, and a chain of facts made from facts. The erased words are one canary
/// and the kept words another, so a check finds a copy in any table or file.
struct Scene {
    static let erasedScope = "erased-chat"
    static let keptScope = "kept-chat"
    static let chainLength = 7

    let store: Store
    let erased: String
    let kept: String
    let machine: Machine
    let folder: WorkObject
    var erasedLines: [Data] = []
    var keptLines: [Data] = []
    var erasedFacts: [Int64] = []
    var keptFacts: [Int64] = []
    var chain: [Int64] = []
    var erasedRun: RunID = 0
    var keptRun: RunID = 0
    var proposal: PageProposalID = 0
    var product: Int64 = 0
    var keptProduct: Int64 = 0

    var erasure: EvidenceErasure { .grant(kind: SourceDescriptor.typedNote.consent, label: Self.erasedScope) }

    static func make(in directory: URL, linesPerChat: Int = 2, kind: SourceKind = .whatsapp) throws -> Scene {
        let store = try Store(directory: directory)
        let owner = try PersonID("owner")
        let folder = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Folder (synthetic)")
        let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: folder.id)
        var scene = Scene(
            store: store, erased: canary("erased"), kept: canary("kept"), machine: machine, folder: folder)
        scene.erasedLines = try scene.write(Self.erasedScope, word: scene.erased, count: linesPerChat, owner: owner)
        scene.keptLines = try scene.write(Self.keptScope, word: scene.kept, count: linesPerChat, owner: owner)
        (scene.erasedRun, scene.erasedFacts) = try scene.read(
            Self.erasedScope, word: scene.erased, lines: scene.erasedLines)
        (scene.keptRun, scene.keptFacts) = try scene.read(Self.keptScope, word: scene.kept, lines: scene.keptLines)
        scene.chain = try scene.makeChain()
        try scene.addEvent()
        try scene.addSummary()
        try scene.addProposal(owner: owner)
        try scene.addProducts()
        try scene.addMochi()
        try scene.addLogs()
        return scene
    }

    static func text(_ word: String, _ index: Int) -> String {
        "Asha: please send me the deck \(word) by Friday \(index)"
    }

    private func write(_ scope: String, word: String, count: Int, owner: PersonID) throws -> [Data] {
        let lines = try (0..<count).map { index in
            ObservedLine(
                line: Line(
                    entity: try EntityKey.web(site: "workbench", container: scope, itemID: "line-\(index + 1)"),
                    text: Self.text(word, index), readerVersion: Store.readerVersion),
                eventTime: UTCInstant(Date()), actor: WhatsAppAudience.owner, messageRef: "L\(index + 1)")
        }
        guard let grant = CaptureGrant.byHand(SourceDescriptor.typedNote.consent, label: scope, at: Date()) else {
            throw CheckFailure("no grant")
        }
        _ = try store.record(
            SourceReading(
                grant: grant, label: scope, container: scope,
                audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [String]()), lines: lines,
                cursorAfter: nil, readerVersion: Store.readerVersion),
            of: .typedNote, owner: owner)
        return lines.map { Data($0.line.id.bytes) }
    }

    /// One run that read the lines, and one fact per line that quotes it, saved the way a reading saves them.
    private func read(_ scope: String, word: String, lines: [Data]) throws -> (RunID, [Int64]) {
        let run = try store.beginRun(
            task: machine.spec.task, model: "synthetic", prompt: "none",
            input: (0..<lines.count).map { Self.text(word, $0) }.joined(separator: "\n"), kinds: [.typed],
            window: lines.enumerated().map { WindowLine(number: Int64($0.offset + 1), lineID: $0.element) })
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "reply \(word)")
        let day = WorkDay(containing: Date())
        let items = (0..<lines.count).map { index -> Item in
            let text = Self.text(word, index)
            let number = Int64(index + 1)
            let quote = "send me the deck \(word)"
            let start = text.range(of: quote)!
            return Item(
                task: machine.spec.task, day: day, scope: scope, source: .whatsapp, citeFirst: number,
                citeLast: min(number + 1, Int64(lines.count)), start: Date(), end: Date(),
                fields: ["who": "Asha \(scope)", "owes": "you", "kind": "ask", "text": "Send the deck \(word)"],
                quote: quote, run: run,
                quoteSpan: QuoteSpan(
                    line: number, part: 0, start: text.distance(from: text.startIndex, to: start.lowerBound),
                    end: text.distance(from: text.startIndex, to: start.upperBound)))
        }
        try store.saveReading(
            HelperReader.Result(items: items, dropped: 0, run: run), of: machine.spec, day: day, scope: scope,
            grant: try wholeGrant(.whatsapp, scope))
        let stored = try store.queries.items(of: machine.spec.task, day: day, scope: scope)
        return (run, stored.compactMap(\.id))
    }

    func wholeGrant(_ kind: SourceKind, _ label: String?) throws -> CaptureGrant {
        var policy = CapturePolicy()
        policy.switches[kind] = true
        if let label { policy.allowList[kind] = [label] }
        guard let grant = policy.authorize(CaptureRequest(kind: kind, label: label), at: Date()).grant else {
            throw CheckFailure("no grant for \(kind)")
        }
        return grant
    }

    /// Facts made from facts, a link at a time: the words of the first are copied along the chain.
    private func makeChain() throws -> [Int64] {
        let now = Date()
        return try store.writer.write { db in
            var made: [Int64] = []
            var previous = erasedFacts[0]
            for index in 0..<Self.chainLength {
                let id = try Store.insertItem(
                    db,
                    Item(
                        task: machine.spec.task, day: WorkDay(containing: now), scope: "chain", source: .whatsapp,
                        citeFirst: 0, citeLast: 0, start: now, end: now,
                        fields: ["who": "Chain \(index)", "text": "copied \(erased)"],
                        quote: "chain \(erased) \(index)",
                        run: keptRun),
                    at: now)
                try Store.derive(
                    [
                        Derivation(
                            node: Node(.item, id), sources: [.quotes(Node(.item, previous))], run: keptRun,
                            rule: "chain")
                    ],
                    at: now, in: db)
                made.append(id)
                previous = id
            }
            return made
        }
    }

    private func addEvent() throws {
        try store.writer.write { db in
            try store.addEvent(
                db, item: erasedFacts[0], kind: .restate, at: Date(), by: (erasedRun, 2, "again \(erased)"))
        }
    }

    private func addSummary() throws {
        let stored = [(Self.erasedScope, erased, erasedRun), (Self.keptScope, kept, keptRun)].map { scope, word, run in
            StoredSummary(
                fingerprint: "f", kinds: [.whatsapp],
                summary: Summary(
                    scope: "who: Asha \(scope)", short: Summary.Line(text: "Summary \(word)", cites: []), details: [],
                    run: run))
        }
        try store.saveSummaries(
            stored, day: WorkDay(containing: Date()), task: machine.spec.task, field: "who")
    }

    /// A page proposal with one block that cites the first fact of the erased chat, and one with a fact of the kept chat.
    private func addProposal(owner: PersonID) throws {
        let facts = try store.queries.items(ids: [erasedFacts[0], keptFacts[0]])
        let run = try store.beginRun(
            task: PageComposer.task, model: "synthetic", prompt: "by hand", input: "no model call", kinds: [.typed],
            window: [WindowLine(number: 1, lineID: erasedLines[0])])
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        let sentence = CitedText(text: "Asha waits \(erased).", cites: [.fact(erasedFacts[0]), .fact(keptFacts[0])])
        let (page, verdicts) = PageGate(catalog: PageCatalog(spec: machine.spec, items: facts)).apply(
            [.insert(.text(sentence), after: nil)], to: MachinePage())
        guard let pageObject = machine.page else { throw CheckFailure("no page") }
        _ = verdicts
        try store.propose(
            PageProposal(note: "A line \(erased).", verdicts: verdicts, page: page, run: run), on: pageObject,
            by: machine.id, request: "Show the follow-ups", owner: owner)
    }

    /// Two work products with a claim each: one cites a line of the erased chat, one a line of the kept chat.
    private mutating func addProducts() throws {
        let run = try store.beginRun(
            task: "research", model: "synthetic", prompt: "none", input: "claims", kinds: [.typed])
        for (lines, word) in [(erasedLines, erased), (keptLines, kept)] {
            let claim = ProductClaim(
                text: "Claim \(word)", cites: [Cite(source: .line(lines[0]), quote: "send me the deck \(word)")])
            let saved = try store.saveProduct(
                WorkProduct(
                    taskType: WorkProduct.researchTask, object: folder.id, subject: "Acme", question: "q",
                    text: "Note \(word)", claims: [claim]), writer: run,
                grant: try wholeGrant(.whatsapp, Self.erasedScope),
                versions: JudgeVersions(parts: ["structure": "s"]), catchChance: 0, draw: { _ in nil },
                isAudited: { _ in false })
            let verdict = StageVerdict(stage: .structure, verdict: .pass, reason: "ok", detail: "detail \(word)")
            try store.saveJudgment(
                ProductJudgment(
                    claims: [ClaimJudgment(structure: verdict, grounding: nil)], advice: [],
                    versions: JudgeVersions(parts: ["structure": "s"])), of: saved)
            try store.mark(product: saved.id, as: .edit("Edited \(word)"), surface: .machinePage)
            if word == erased { product = saved.id } else { keptProduct = saved.id }
        }
    }

    /// A failed run whose error holds the words, a log entry that names a fact, and a link event that copies a fact.
    private func addLogs() throws {
        let failed = try store.beginRun(
            task: "failing", model: "synthetic", prompt: "none", input: "x", kinds: [.typed],
            window: [WindowLine(number: 1, lineID: erasedLines[0])])
        try store.failRun(
            failed, model: "synthetic",
            error: NSError(domain: "check", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad reply \(erased)"]))
        try store.log(
            "make_reminder", target: machine.spec.task,
            detail: ["item": String(erasedFacts[0]), "title": "Remind \(erased)"])
        guard let fact = try store.queries.items(ids: [erasedFacts[0]]).first else { throw CheckFailure("no fact") }
        try store.append([
            WorkEvent(
                object: folder.id, author: "me", clock: 1, at: Date(), kind: .link,
                item: LinkedItem(machine: machine, item: fact, audience: []))
        ])
    }

    /// A work product that cites a page snapshot, with its claim, verdict and mark. Returns the product and the word.
    func addSnapshotProduct() throws -> (product: Int64, word: String) {
        let word = canary("page")
        let snapshot = try store.writer.write { db -> Int64 in
            try db.execute(
                sql: """
                    INSERT INTO page_snapshot(url, fetched_at, content_hash, text)
                    VALUES ('https://example.com/a', '2026-11-20T10:00:00Z', ?, ?)
                    """, arguments: [String(repeating: "a", count: 64), "page \(word) text"])
            return db.lastInsertedRowID
        }
        let run = try store.beginRun(task: "research", model: "synthetic", prompt: "none", input: "claims", kinds: [])
        let saved = try store.saveProduct(
            WorkProduct(
                taskType: WorkProduct.researchTask, object: folder.id, subject: "Acme", question: "q",
                text: "Note \(word)",
                claims: [
                    ProductClaim(
                        text: "Claim \(word)", cites: [Cite(source: .page(snapshot: snapshot), quote: "page \(word)")])
                ]), writer: run, grant: try wholeGrant(.whatsapp, Self.erasedScope),
            versions: JudgeVersions(parts: ["structure": "s"]), catchChance: 0, draw: { _ in nil },
            isAudited: { _ in false })
        let verdict = StageVerdict(stage: .structure, verdict: .pass, reason: "ok", detail: "detail \(word)")
        try store.saveJudgment(
            ProductJudgment(
                claims: [ClaimJudgment(structure: verdict, grounding: nil)], advice: [],
                versions: JudgeVersions(parts: ["structure": "s"])), of: saved)
        try store.mark(product: saved.id, as: .edit("Edited \(word)"), surface: .machinePage)
        return (saved.id, word)
    }

    private func addMochi() throws {
        let run = try store.beginRun(
            task: "mochi", model: "synthetic", prompt: "none", input: "x", kinds: [.screen],
            window: [WindowLine(number: 1, lineID: erasedLines[0])])
        try store.saveProposals(
            Mochi.Result(
                proposals: [
                    Proposal(
                        run: run, name: "Name", template: "t", brief: "brief", why: "why \(erased)", view: "table",
                        evidence: [1, 2, 3], decision: .waiting)
                ], dropped: 0, run: run), grant: try wholeGrant(.screen, nil))
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
