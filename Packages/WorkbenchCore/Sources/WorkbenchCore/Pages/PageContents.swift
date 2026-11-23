import Foundation
import Kernel

/// Who reads a page: the people in the audience, and the grants and the roster that say who may read each source. A
/// block whose words rest on sources is shown only when its label admits every one of them.
public struct PageViewer: Sendable {
    public var audience: Set<PersonID>
    public var grants: Grants
    public var roster: Kernel.Roster

    public init(audience: Set<PersonID>, grants: Grants, roster: Kernel.Roster) {
        self.audience = audience
        self.grants = grants
        self.roster = roster
    }

    /// Whether this reader may see the words of `block`, whose stored label is `label`. A block with no label of its
    /// own is shown; a block that should have one and has none (its sources are not all known) is not.
    func shows(_ block: MachineBlock, labelled label: Label?) -> Bool {
        guard block.hasLabel else { return true }
        return label?.admits(audience, grants: grants, roster: roster) ?? false
    }
}

/// A page as one reader sees it: the order of all its blocks, what each machine block is, the person's paragraphs, and
/// which machine blocks had their words erased. A machine block this reader may not see is left out of all of them.
public struct PageContents: Equatable, Sendable {
    public var page: MachinePage
    public var notes: [NoteBlock]
    public var erased: Set<MachineBlockID>

    public init(page: MachinePage, notes: [NoteBlock], erased: Set<MachineBlockID>) {
        self.page = page
        self.notes = notes
        self.erased = erased
    }
}

/// A proposal that waits for the person: the machine's note, what it asks for, and the blocks it brings in, so a view
/// can show the page as it would be. A block this reader may not see is left out of `blocks`.
public struct PendingProposal: Equatable, Sendable {
    public var id: PageProposalID
    public var machine: Int64
    public var run: RunID
    public var requestLine: Data
    public var note: String
    public var operations: [StoredOperation]
    public var blocks: [MachineBlockID: MachineBlock]
    public var erased: Set<MachineBlockID>
    public var at: Date

    public init(
        id: PageProposalID, machine: Int64, run: RunID, requestLine: Data, note: String, operations: [StoredOperation],
        blocks: [MachineBlockID: MachineBlock], erased: Set<MachineBlockID>, at: Date
    ) {
        self.id = id
        self.machine = machine
        self.run = run
        self.requestLine = requestLine
        self.note = note
        self.operations = operations
        self.blocks = blocks
        self.erased = erased
        self.at = at
    }
}
