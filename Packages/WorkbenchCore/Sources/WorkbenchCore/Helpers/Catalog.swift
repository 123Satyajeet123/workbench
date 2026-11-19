import Foundation

/// A machine one teammate shares with the team: its spec, who made it, and its record in counts. Never its items, its
/// quotes, or any captured data: what leaves a Mac is the recipe and how well it did, nothing it read.
public struct SharedMachine: Codable, Sendable, Equatable, Identifiable {
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

    /// One file per author and machine, so each person only ever writes their own files.
    public static func fileName(author: String, task: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._"))
        let safe = { (text: String) in
            String(String(text.unicodeScalars.filter(allowed.contains)).drop { $0 == "." })
        }
        return "\(safe(author))--\(safe(task)).json"
    }

    public func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(
            to: folder.appending(path: Self.fileName(author: author, task: spec.task)), options: .atomic)
    }

    public static func remove(author: String, task: String, from folder: URL) throws {
        let file = folder.appending(path: fileName(author: author, task: task))
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Every shared machine in the folder, newest first, and the files that could not be read.
    public static func read(from folder: URL) -> (machines: [SharedMachine], unreadable: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var machines: [SharedMachine] = []
        var unreadable: [String] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let machine = try? decoder.decode(SharedMachine.self, from: data)
            {
                machines.append(machine)
            } else {
                unreadable.append(file.lastPathComponent)
            }
        }
        return (machines.sorted { $0.sharedAt > $1.sharedAt }, unreadable.sorted())
    }
}
