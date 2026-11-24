import Foundation
import Kernel
import Lines

/// What one import of a connections file did.
public struct LinkedInImportReport: Sendable, Equatable {
    /// Connections in the file.
    public var connections = 0
    /// Rows the file had without a profile URL: they cannot be named, so they are not kept.
    public var skippedRows = 0
    /// Lines that are new or changed since the last import.
    public var written = 0
    /// Lines of connections that did not change.
    public var unchanged = 0
    /// Lines erased: the old line of a changed connection, and every line of a connection the file no longer has.
    public var erased = 0
}

extension Store {
    private static let linkedInLabel = "connections"

    /// Reads the person's `Connections.csv` and makes the stored connections equal to it, in one transaction: a
    /// connection is a line named by its profile URL, a changed connection replaces its line, and a connection the file
    /// no longer has is erased with the one erase path. Throws `LinkedInExportError` for a file that is not one.
    @discardableResult
    public func importLinkedInConnections(_ file: Data, owner: PersonID) throws -> LinkedInImportReport {
        let parsed = try LinkedInConnections.parse(file)
        let importedAt = clock()
        let lines = try parsed.connections.map { connection in
            ObservedLine(
                line: Line(
                    entity: try EntityKey.web(
                        site: "linkedin", container: Self.linkedInLabel, itemID: connection.profileURL),
                    text: connection.words, readerVersion: Self.readerVersion),
                eventTime: UTCInstant(importedAt), actor: connection.name, messageRef: connection.profileURL)
        }
        let (written, erasure) = try recordOwn(
            lines, of: .linkedinExport, label: Self.linkedInLabel, container: Self.linkedInLabel, owner: owner
        ) { db in
            try Self.eraseEvidence(
                EvidenceErasure(
                    grant: Self.grantID(kind: .linkedinExport, label: Self.linkedInLabel), lastSeenBefore: importedAt),
                in: db)
        }
        try finishErase(removedRows: erasure.lines > 0)
        return LinkedInImportReport(
            connections: lines.count, skippedRows: parsed.skipped, written: written.inserted,
            unchanged: written.seenAgain, erased: erasure.lines)
    }
}
