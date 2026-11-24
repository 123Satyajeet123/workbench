import Foundation
import GRDB
import Kernel
import Lines

extension SourceDescriptor {
    private static let noteGrammar = """
        the person's own notes about one project. Each line is one paragraph in the person's words.
        """

    /// Project notes: what the person writes. Each paragraph is one line, kept under the block's name.
    public static let note = SourceDescriptor(
        key: "workbench.note", name: "Your note", consent: .note, grammar: noteGrammar, retention: .note,
        obtainedBy: .db, editWindow: 0, ownWriting: true)
}

extension EntityKey {
    static func block(_ block: BlockID, of note: NoteID) throws(EntityKeyError) -> EntityKey {
        try .note(noteID: note.rawValue, blockID: block.rawValue)
    }
}

/// One write of a note, as an evidence source: the lines of the blocks that changed, the tombstones of the blocks that
/// ended, and the note's structure. `Store.ingest` writes them in one transaction, after the policy allowed the note.
struct NoteSource: EvidenceSource {
    enum Work: Sendable {
        case save(NoteChange)
        case erase(NoteID)

        var note: NoteID {
            switch self {
            case .save(let change): change.note
            case .erase(let note): note
            }
        }
    }

    static let readerVersion = "note 1"
    /// The owner is the actor of every line of a note.
    static let actor = "me"
    static let audience = AudienceDigest(owner: actor, members: [])

    let store: Store
    let work: Work

    var descriptor: SourceDescriptor { .note }

    func sightings(policy: CapturePolicy, now: Date) throws -> [ContainerSighting] { [] }

    func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead {
        let note = work.note
        guard
            let grant = try await store.currentPolicy().authorize(
                CaptureRequest(kind: .note, label: note.rawValue), at: now
            ).grant
        else { throw EvidenceError.consentWithdrawn }
        let plan = try store.queries.notePlan(of: work, at: now)
        var reading = SourceReading(
            grant: grant, label: note.rawValue, container: note.rawValue, audience: Self.audience,
            lines: plan.lines, cursorAfter: nil, readerVersion: Self.readerVersion)
        reading.structure = plan.structure
        return SourceRead(readings: [reading])
    }
}

/// What one write puts in the store.
struct NotePlan {
    var lines: [ObservedLine]
    var structure: ContainerStructure?
}

extension Queries {
    func notePlan(of work: NoteSource.Work, at now: Date) throws -> NotePlan {
        switch work {
        case .save(let change): try savePlan(change, at: now)
        case .erase(let note): try erasePlan(of: note, at: now)
        }
    }

    private func savePlan(_ change: NoteChange, at now: Date) throws -> NotePlan {
        let note = change.note
        let written = try change.blocks.map { block in
            observed(
                Line(entity: try .block(block.id, of: note), text: block.text, readerVersion: NoteSource.readerVersion),
                block: block.id, at: now)
        }
        var gone: [BlockID] = []
        var supersessions: [ContainerStructure.Supersession] = []
        for ending in change.endings {
            switch ending {
            case .deleted(let block): gone += try blocks(joinedInto: block, of: note)
            case .merged(let block, let into):
                supersessions.append(
                    ContainerStructure.Supersession(
                        entity: try .block(block, of: note), into: try .block(into, of: note)))
            }
        }
        let tombstones = try gone.map { observed(try tombstone($0, of: note), block: $0, at: now) }
        return NotePlan(
            lines: written + tombstones,
            structure: ContainerStructure(
                order: try orderKeys(of: change), supersessions: supersessions))
    }

    /// The keys of the order the person sees: the page order when the editor gave one, else the paragraphs.
    private func orderKeys(of change: NoteChange) throws -> [EntityKey] {
        try (change.pageOrder ?? change.order.map(PageBlockRef.note)).map { place in
            switch place {
            case .note(let block): try .block(block, of: change.note)
            case .machine(let block): try .machineBlock(objectID: change.note.rawValue, blockID: block.rawValue)
            }
        }
    }

    private func erasePlan(of note: NoteID, at now: Date) throws -> NotePlan {
        let tombstones = try blocks(of: note).map { observed(try tombstone($0, of: note), block: $0, at: now) }
        return NotePlan(lines: tombstones, structure: ContainerStructure(order: []))
    }

    private func tombstone(_ block: BlockID, of note: NoteID) throws -> Line {
        .tombstone(entity: try .block(block, of: note), readerVersion: NoteSource.readerVersion)
    }

    private func observed(_ line: Line, block: BlockID, at now: Date) -> ObservedLine {
        ObservedLine(line: line, eventTime: UTCInstant(now), actor: NoteSource.actor, messageRef: block.rawValue)
    }
}
