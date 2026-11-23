import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

struct DemoFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}

func expect<Value: Equatable>(_ actual: Value, _ wanted: Value, _ what: String) throws {
    guard actual == wanted else { throw DemoFailure("\(what): got \(actual), wanted \(wanted)") }
}

/// What the demo works on: a store in a temporary folder, a folder with one machine and its page, three paragraphs of
/// the person on that page, and two facts that quote two stored lines.
struct World {
    static let scope = "demo"
    static let paragraphTexts = ["Budget talk with Asha.", "Next steps are unclear.", "A paragraph to delete."]
    static let sourceTexts = ["Asha: please send me the deck by Friday", "Ravi: I will send the numbers on Monday"]
    static let quotes = ["send me the deck by Friday", "send the numbers on Monday"]

    let directory: URL
    let store: Store
    let owner: PersonID
    let machine: Machine
    let page: WorkObjectID
    let paragraphs: [BlockID]
    let facts: [Item]
    let reader: PageViewer
    let stranger: PageViewer

    var note: NoteID { NoteID(object: page)! }

    static func make(in directory: URL) async throws -> World {
        let store = try Store(directory: directory)
        let owner = try PersonID("owner")
        let folder = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Follow-ups (synthetic)")
        let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: folder.id)
        guard let page = machine.page, let note = NoteID(object: page) else { throw DemoFailure("no page") }
        let paragraphs = paragraphTexts.map { _ in BlockID() }
        try await store.saveNote(
            NoteChange(
                note: note, blocks: zip(paragraphs, paragraphTexts).map { NoteBlock(id: $0.0, text: $0.1) },
                endings: [], order: paragraphs), owner: owner)
        let facts = try makeFacts(in: store, of: machine, owner: owner)
        let strangerID = try PersonID("stranger")
        let grants = Grants([try ownerGrant(.typedNote, owner), try ownerGrant(.note, owner)])
        let roster = Roster(members: [owner, strangerID])
        return World(
            directory: directory, store: store, owner: owner, machine: machine, page: page, paragraphs: paragraphs,
            facts: facts, reader: PageViewer(audience: [owner], grants: grants, roster: roster),
            stranger: PageViewer(audience: [strangerID], grants: grants, roster: roster))
    }

    /// Two stored lines, one run that read them, and one fact quoting each, saved the way a reading saves them.
    private static func makeFacts(in store: Store, of machine: Machine, owner: PersonID) throws -> [Item] {
        let lines = try sourceTexts.enumerated().map { index, text in
            ObservedLine(
                line: Line(
                    entity: try EntityKey.web(site: "workbench", container: scope, itemID: "line-\(index + 1)"),
                    text: text, readerVersion: Store.readerVersion),
                eventTime: UTCInstant(Date()), actor: WhatsAppAudience.owner, messageRef: "L\(index + 1)")
        }
        guard let byHand = CaptureGrant.byHand(SourceDescriptor.typedNote.consent, label: scope, at: Date()) else {
            throw DemoFailure("no reading")
        }
        let reading = SourceReading(
            grant: byHand, label: scope, container: scope,
            audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [String]()), lines: lines,
            cursorAfter: nil, readerVersion: Store.readerVersion)
        _ = try store.record(reading, of: .typedNote, owner: owner)
        let run = try store.beginRun(
            task: "demo.facts", model: "synthetic", prompt: "none", input: sourceTexts.joined(separator: "\n"),
            kinds: [.typed],
            window: lines.enumerated().map {
                WindowLine(number: Int64($0.offset + 1), lineID: Data($0.element.line.id.bytes))
            })
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        let label = Label(source: try SourceDescriptor.typedNote.sourceID(owner: owner))
        let fields = [
            ["who": "Asha", "owes": "you", "kind": "ask", "text": "Send Asha the deck by Friday"],
            ["who": "Ravi", "owes": "them", "kind": "promise", "text": "Ravi sends the numbers on Monday"],
        ]
        let today = WorkDay(containing: Date())
        let items = (0..<2).map { index -> Item in
            let number = Int64(index + 1)
            let quoted = span(of: quotes[index], in: sourceTexts[index], line: number)
            return Item(
                task: machine.spec.task, day: today, scope: scope, source: .whatsapp, citeFirst: number,
                citeLast: number, start: Date(), end: Date(), fields: fields[index], quote: quotes[index], run: run,
                quoteSpan: quoted, label: label, authority: .ownWords)
        }
        var policy = CapturePolicy()
        policy.switches[.whatsapp] = true
        policy.allowList[.whatsapp] = [scope]
        guard let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: scope), at: Date()).grant else {
            throw DemoFailure("no grant")
        }
        try store.saveReading(
            HelperReader.Result(items: items, dropped: 0, run: run), of: machine.spec, day: WorkDay(containing: Date()),
            scope: scope, grant: grant)
        let stored = try store.queries.items(of: machine.spec.task, day: WorkDay(containing: Date()), scope: scope)
        return try quotes.map { quote in
            guard let fact = stored.first(where: { $0.quote == quote }) else { throw DemoFailure("fact not saved") }
            return fact
        }
    }

    private static func span(of quote: String, in text: String, line: Int64) -> QuoteSpan {
        let start =
            text.range(of: quote).map {
                text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: $0.lowerBound)
            } ?? 0
        return QuoteSpan(line: line, part: 0, start: start, end: start + quote.unicodeScalars.count)
    }

    private static func ownerGrant(_ descriptor: SourceDescriptor, _ owner: PersonID) throws -> Grant {
        Grant(
            signer: owner, source: Kernel.Source(owner: owner, key: try SourceKey(descriptor.key)), readers: [owner],
            epoch: 1)
    }
}
