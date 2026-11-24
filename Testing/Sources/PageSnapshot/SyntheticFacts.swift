import Foundation
import Kernel
import Lines

@testable import WorkbenchCore

/// Stored lines, one run that read them, and one fact quoting each line, saved the way a reading saves them. The
/// lines, quotes and fields are synthetic and in the same order. No fact is picked for the person's audit, which a
/// reading picks at random: a fixture that changes from run to run is not a fixture. Nothing here reads the person's store or the network.
@MainActor
public func saveSyntheticFacts(
    in store: Store, of machine: Machine, owner: PersonID, scope: String, sources: [String], quotes: [String],
    fields: [[String: String]]
) throws -> [Item] {
    let lines = try sources.enumerated().map { index, text in
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
        task: "\(scope).facts", model: "synthetic", prompt: "none", input: sources.joined(separator: "\n"),
        kinds: [.typed],
        window: lines.enumerated().map {
            WindowLine(number: Int64($0.offset + 1), lineID: Data($0.element.line.id.bytes))
        })
    try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
    let label = Label(source: try SourceDescriptor.typedNote.sourceID(owner: owner))
    let today = WorkDay(containing: Date())
    let items = sources.indices.map { index -> Item in
        let number = Int64(index + 1)
        let text = sources[index]
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
        grant: grant, isAudited: { _ in false })
    let stored = try store.queries.items(of: machine.spec.task, day: today, scope: scope)
    return try quotes.map { quote in
        guard let fact = stored.first(where: { $0.quote == quote }) else { throw RenderFailure("fact not saved") }
        return fact
    }
}
