import Foundation
import GRDB
import Kernel
import Lines

extension HelperSpec {
    /// The follow-ups someone took on in a recorded call. Each is an open fact until it is done or dropped; one the
    /// founder took on asks the founder, so Today lists it under what the founder owes.
    public static let callFollowUps = HelperSpec(
        task: "call.actions", source: .callTranscript,
        brief: """
            You read the transcript of one call the founder recorded. Give one item for each concrete follow-up \
            someone on the call took on: a thing they will do, send or decide. Use only what was said in the call. \
            A wish, an idea or an open question gives no item. Speech recognition makes mistakes; when a word is \
            clearly misheard, write what was meant only if it is obvious.
            """,
        fields: [
            Field(
                "person", .text(required: true),
                meaning:
                    "Who does it: the founder's name as the Founder list gives it, a person's name when it was said, or \"Them\"."
            ),
            Field("kind", .choice(["commitment"]), meaning: "commitment: someone on the call takes on a result."),
            Field("text", .text(required: true), meaning: "What will be done, in one short English line."),
            Field("when", .time, meaning: Field.dueWords),
            Field(
                "asks", .choice(["founder", "team"]),
                meaning: "founder: the founder took it on, or it waits on the founder. team: every other follow-up."),
        ],
        citation: .one, view: .checklist(by: "asks"), title: "text", badges: ["person"],
        tones: ["commitment": .neutral], itemsNoun: "follow-ups", nudge: nil,
        lifecycle: .callFollowUps)
}

extension HelperSpec.Lifecycle {
    /// A follow-up of a call is open until it is done or dropped; its owner is the person who took it on.
    public static let callFollowUps = HelperSpec.Lifecycle(
        field: "kind", open: ["commitment"], outcomes: ["done", "dropped"], owner: "person")
}

/// Opens the follow-ups said in one call as facts of `HelperSpec.callFollowUps`: one `HelperReader` run over the
/// call's transcript lines that no earlier reading of the machine saw, kept by the verifier and written by
/// `Store.saveReading` under the call app's consent. The follow-ups still open from earlier calls are shown, so a later
/// call can restate one or say it is done. Review never asks about a follow-up, so none is picked for a random check.
public struct CallFollowUps: Sendable {
    public let model: RecordedModel

    public init(model: RecordedModel) { self.model = model }

    /// `me` is the founder's name as the lines show it.
    public func read(_ recording: Recording, lines: [StoredLine], me: String, into store: Store) async throws {
        let spec = HelperSpec.callFollowUps
        let day = WorkDay(containing: recording.startedAt)
        let invited = recording.guests ?? []
        let evidence = EvidenceSet(
            lines: lines.map { recording.evidence($0, me: me) },
            context: invited.isEmpty ? ["founder": [me]] : ["founder": [me], "invited": invited])
        let unread = try store.queries.unread(evidence, by: spec.task)
        guard !unread.newLines.isEmpty else { return }
        _ = try await HelperReader(spec: spec, model: model).readDay(
            day: day, scope: recording.bundleID, evidence: unread,
            open: { try store.queries.openItems(readBy: spec) },
            save: { result in
                let request = CaptureRequest(kind: .call, label: recording.bundleID)
                guard let grant = try store.queries.policy().authorize(request, at: store.clock()).grant else {
                    throw EvidenceError.consentWithdrawn
                }
                try store.saveReading(
                    result, of: spec, day: day, scope: recording.bundleID, grant: grant, isAudited: { _ in false })
            })
    }
}

extension Queries {
    /// The ids of the follow-ups a call opened: the facts of `HelperSpec.callFollowUps` whose cited lines, in the
    /// window of the run that made them, are lines of the call.
    func followUps(of call: Recording) throws -> Set<Int64> {
        try reader.read { db in
            try Set(
                Int64.fetchAll(
                    db,
                    sql: """
                        SELECT item.id FROM item
                        JOIN run_line w ON w.run_id = item.run_id
                            AND w.ordinal BETWEEN item.cite_first AND item.cite_last
                        JOIN evidence e ON e.line_id = w.line_id
                        WHERE item.task = ? AND e.container = ?
                        """, arguments: [HelperSpec.callFollowUps.task, call.container]))
        }
    }
}
