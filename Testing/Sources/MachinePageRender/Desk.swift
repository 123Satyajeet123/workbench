import CaptureService
import Foundation
import GRDB
import Kernel
import Lines
import LocalSources

@testable import WorkbenchCore
@testable import WorkbenchUI

struct RenderFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}

/// A machine and its page in a new store in a temporary folder: three paragraphs are not needed, two are, and two
/// facts quote two stored lines. Nothing here reads the person's store, the network or the Keychain.
@MainActor
final class Desk {
    static let scope = "render"
    static let paragraphTexts = ["Budget talk with Asha.", "Next steps are unclear."]
    static let sourceTexts = ["Asha: please send me the deck by Friday", "Ravi: I will send the numbers on Monday"]
    static let quotes = ["send me the deck by Friday", "send the numbers on Monday"]

    let folder = FileManager.default.temporaryDirectory.appending(path: "machine-page-render-\(UUID().uuidString)")
    let store: Store
    let owner: PersonID
    let crew: Crew
    let machine: Machine
    let helper: HelperModel
    let page: MachinePageModel
    let paragraphs: [BlockID]
    let facts: [Item]

    init() async throws {
        let store = try Store(directory: folder)
        let owner = try PersonID("render-owner")
        let work = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Follow-ups (synthetic)")
        let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: work.id)
        guard let pageID = machine.page, let note = NoteID(object: pageID) else { throw RenderFailure("no page") }
        let paragraphs = Self.paragraphTexts.map { _ in BlockID() }
        try await store.saveNote(
            NoteChange(
                note: note, blocks: zip(paragraphs, Self.paragraphTexts).map { NoteBlock(id: $0.0, text: $0.1) },
                endings: [], order: paragraphs), owner: owner)
        let facts = try Self.makeFacts(in: store, of: machine, owner: owner)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
            makeModel: nil, notifier: QuietNotifier(), owner: .success(owner),
            whatsAppContainer: folder.appending(path: "no-whatsapp"))
        guard let helper = crew.helper(id: machine.id), let page = helper.pageModel else {
            throw RenderFailure("the machine has no page model")
        }
        (self.store, self.owner, self.crew, self.machine, self.helper, self.page) = (
            store, owner, crew, machine, helper, page
        )
        (self.paragraphs, self.facts) = (paragraphs, facts)
    }

    func close() { try? FileManager.default.removeItem(at: folder) }

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
            throw RenderFailure("no reading")
        }
        let reading = SourceReading(
            grant: byHand, label: scope, container: scope,
            audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [String]()), lines: lines,
            cursorAfter: nil, readerVersion: Store.readerVersion)
        _ = try store.record(reading, of: .typedNote, owner: owner)
        let run = try store.beginRun(
            task: "render.facts", model: "synthetic", prompt: "none", input: sourceTexts.joined(separator: "\n"),
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
            let text = sourceTexts[index]
            let start = text.range(of: quotes[index]).map {
                text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: $0.lowerBound)
            }
            let span = QuoteSpan(
                line: number, part: 0, start: start ?? 0, end: (start ?? 0) + quotes[index].unicodeScalars.count)
            return Item(
                task: machine.spec.task, day: today, scope: scope, source: .whatsapp, citeFirst: number,
                citeLast: number, start: Date(), end: Date(), fields: fields[index], quote: quotes[index], run: run,
                quoteSpan: span, label: label, authority: .ownWords)
        }
        var policy = CapturePolicy()
        policy.switches[.whatsapp] = true
        policy.allowList[.whatsapp] = [scope]
        guard let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: scope), at: Date()).grant else {
            throw RenderFailure("no grant")
        }
        try store.saveReading(
            HelperReader.Result(items: items, dropped: 0, run: run), of: machine.spec, day: today, scope: scope,
            grant: grant)
        let stored = try store.queries.items(of: machine.spec.task, day: today, scope: scope)
        return try quotes.map { quote in
            guard let fact = stored.first(where: { $0.quote == quote }) else { throw RenderFailure("fact not saved") }
            return fact
        }
    }
}

final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}
