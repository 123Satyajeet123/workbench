import Foundation

public struct SharedMachine: TeamFile, Equatable, Identifiable {
    public static let subfolder = ""

    public struct Record: Codable, Sendable, Equatable {
        public var runs = 0
        public var kept = 0
        public var dropped = 0
        public var audited = 0
        public var auditedPrecision: Double?
        public var heldOutAnswers = 0
        public var heldOutWrong = 0

        public init() {}

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
    public var version: String { Digest.sha256((try? Coding.json(spec)) ?? spec.brief) }

    public func approvers(in reviews: [MachineReview]) -> [String] {
        let fair = reviews.filter { $0.author == author && $0.task == spec.task && $0.reviewer != author }
            .filter { $0.version == version }
        return Array(Set(fair.filter { $0.approve }.map(\.reviewer))).sorted()
    }

    public var owner: String { author }
    public var fileParts: [String] { [spec.task] }
}

public enum TeamFolder {
    public static func safe(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._"))
        return String(String(text.unicodeScalars.filter(allowed.contains)).drop { $0 == "." })
    }
}

public protocol TeamFile: Codable, Sendable {
    static var subfolder: String { get }
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

public struct MachineReview: TeamFile, Equatable, Identifiable {
    public static let subfolder = "reviews"

    public var reviewer: String
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
    public var owner: String { reviewer }
    public var fileParts: [String] { [author, task] }
}
