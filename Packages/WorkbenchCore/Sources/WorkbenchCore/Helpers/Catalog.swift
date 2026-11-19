import Foundation

/// A machine one teammate shares with the team: its spec, who made it, and its record in counts. Never its items, its
/// quotes, or any captured data: what leaves a Mac is the recipe and how well it did, nothing it read.
public struct SharedMachine: TeamFile, Equatable, Identifiable {
    public static let subfolder = ""

    /// How the machine did for its author, in counts only.
    public struct Record: Codable, Sendable, Equatable {
        public var runs = 0
        public var kept = 0
        public var dropped = 0
        /// Answers to random picks, and the share right (weighted, as on Runs).
        public var audited = 0
        public var auditedPrecision: Double?
        /// Audit answers on held-out days, and how many were wrong: what trust is earned from.
        public var heldOutAnswers = 0
        public var heldOutWrong = 0

        public init() {}

        /// The record of a machine's current prompt version, from the quality rows.
        public init(task: String, quality: [Quality]) {
            guard let row = quality.first(where: { $0.task == task }) else { return }
            runs = row.runs
            kept = row.kept
            dropped = row.dropped
            audited = row.audited.marks
            auditedPrecision = row.audited.precision
            heldOutAnswers = row.heldOutAudit.answers
            heldOutWrong = row.heldOutAudit.wrong
        }

        /// Trust as its author earned it. It is shown, never carried over: an adopter starts at zero.
        public var trust: Certificate.Status { Certificate(answers: heldOutAnswers, wrong: heldOutWrong).status }
    }

    public var author: String
    public var name: String
    public var template: String
    public var spec: HelperSpec
    public var sharedAt: Date
    public var record: Record

    public init(author: String, machine: Machine, record: Record, at date: Date) {
        self.author = author
        name = machine.name
        template = machine.template
        spec = machine.spec
        sharedAt = date
        self.record = record
    }

    public var id: String { "\(author)/\(spec.task)" }
    /// The version reviews are about: any change to the spec makes a new version, which needs its own review.
    public var version: String { Digest.sha256((try? Coding.json(spec)) ?? spec.brief) }

    /// Approvals of this exact version by people other than its author. A review of an older version, or by the
    /// author, does not count.
    public func approvers(in reviews: [MachineReview]) -> [String] {
        let fair = reviews.filter { $0.author == author && $0.task == spec.task && $0.reviewer != author }
            .filter { $0.version == version }
        return Array(Set(fair.filter { $0.approve }.map(\.reviewer))).sorted()
    }

    public var owner: String { author }
    public var fileParts: [String] { [spec.task] }
}

/// Names in the team folder.
public enum TeamFolder {
    /// Letters, digits, dash, dot and underscore only, with no leading dot: a name cannot leave its folder or hide.
    public static func safe(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._"))
        return String(String(text.unicodeScalars.filter(allowed.contains)).drop { $0 == "." })
    }
}

/// A file one teammate writes in the team folder. Its name is its author and parts, so each person writes only their
/// own files and no name can leave the folder.
public protocol TeamFile: Codable, Sendable {
    /// The folder under the team folder that holds this kind of file; empty for the team folder itself.
    static var subfolder: String { get }
    /// The person who writes the file: only they ever change it.
    var owner: String { get }
    var sharedAt: Date { get }
    var fileParts: [String] { get }
}

extension TeamFile {
    public static func fileName(author: String, parts: [String]) -> String {
        ([author] + parts).map(TeamFolder.safe).joined(separator: "--") + ".json"
    }

    public func write(to folder: URL) throws {
        let folder = Self.folder(in: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(
            to: folder.appending(path: Self.fileName(author: owner, parts: fileParts)), options: .atomic)
    }

    public static func remove(author: String, parts: [String], from folder: URL) throws {
        let file = Self.folder(in: folder).appending(path: fileName(author: author, parts: parts))
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Every file of this kind in the folder, newest first, and the names of files that could not be read.
    public static func read(from folder: URL) -> (files: [Self], unreadable: [String]) {
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: Self.folder(in: folder), includingPropertiesForKeys: nil))
            ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var files: [Self] = []
        var unreadable: [String] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let file = try? decoder.decode(Self.self, from: data) {
                files.append(file)
            } else {
                unreadable.append(url.lastPathComponent)
            }
        }
        return (files.sorted { $0.sharedAt > $1.sharedAt }, unreadable.sorted())
    }

    private static func folder(in team: URL) -> URL { subfolder.isEmpty ? team : team.appending(path: subfolder) }
}

/// One person's review of one version of a shared machine: approve or not, with a note. Each reviewer writes only
/// their own files, in the folder where the machine is shared.
public struct MachineReview: TeamFile, Equatable, Identifiable {
    public static let subfolder = "reviews"

    public var reviewer: String
    /// The machine's author and task, and the version reviewed.
    public var author: String
    public var task: String
    public var version: String
    public var approve: Bool
    public var note: String
    public var sharedAt: Date

    public init(reviewer: String, of machine: SharedMachine, approve: Bool, note: String, at date: Date) {
        self.reviewer = reviewer
        author = machine.author
        task = machine.spec.task
        version = machine.version
        self.approve = approve
        self.note = note
        sharedAt = date
    }

    public var id: String { [reviewer, author, task].joined(separator: "/") }
    /// The file belongs to the reviewer, not to the machine's author.
    public var owner: String { reviewer }
    public var fileParts: [String] { [author, task] }
}
