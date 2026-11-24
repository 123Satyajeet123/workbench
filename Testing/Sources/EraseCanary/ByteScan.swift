import Foundation
import GRDB

/// One place a word sits in a file: the file under the store folder, the byte offset, how the word was written, and what
/// the bytes belong to (a table page of a database file, a frame of its log, or the plain file).
struct Hit: Hashable {
    let file: String
    let offset: Int
    let encoding: String
    let place: String
}

/// The words as bytes: UTF-8, and UTF-16 in both byte orders.
struct WordBytes {
    let encodings: [(name: String, bytes: Data)]

    init(_ word: String) {
        encodings = [
            ("utf8", Data(word.utf8)),
            ("utf16le", word.data(using: .utf16LittleEndian) ?? Data()),
            ("utf16be", word.data(using: .utf16BigEndian) ?? Data()),
        ]
    }
}

/// Scans every byte of every file under a folder, hidden files and backups included, for a word. It never opens the
/// store: a database file is read as bytes, and only a copy of it is opened to name the table of a page that holds a hit.
enum ByteScan {
    static func hits(of word: String, under folder: URL) -> [Hit] {
        let root = folder.resolvingSymlinksInPath().path + "/"
        return files(under: folder).flatMap { file -> [Hit] in
            let name = file.resolvingSymlinksInPath().path.replacingOccurrences(of: root, with: "")
            let data = (try? Data(contentsOf: file, options: .mappedIfSafe)) ?? Data()
            let found = offsets(of: WordBytes(word), in: data)
            guard !found.isEmpty else { return [] }
            let owner = PageOwners(file: file, data: data)
            return found.map {
                Hit(file: name, offset: $0.offset, encoding: $0.encoding, place: owner.place(at: $0.offset))
            }
        }
    }

    static func files(under folder: URL) -> [URL] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        return (walker?.compactMap { $0 as? URL } ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private static func offsets(of word: WordBytes, in data: Data) -> [(offset: Int, encoding: String)] {
        word.encodings.flatMap { encoding in
            var found: [(Int, String)] = []
            var from = data.startIndex
            while !encoding.bytes.isEmpty, let range = data.range(of: encoding.bytes, in: from..<data.endIndex) {
                found.append((range.lowerBound - data.startIndex, encoding.name))
                from = range.upperBound
            }
            return found
        }
    }
}

/// Names what the bytes at an offset belong to. A database file: the page, and the table or index whose page it now is,
/// or "free page" when no table owns it. A write-ahead log: the frame, and the page of the database it holds.
final class PageOwners {
    private let file: URL
    private let data: Data
    private let pageSize: Int
    private let kind: Kind
    private lazy var owners: [Int: String] = Self.owners(of: databaseCopy)

    private enum Kind { case database, log, plain }

    init(file: URL, data: Data) {
        self.file = file
        self.data = data
        let name = file.lastPathComponent
        if name.hasSuffix("-wal") {
            kind = .log
            pageSize = data.count >= 12 ? Int(Self.bigEndian(data, at: 8)) : 4096
        } else if name.hasSuffix(".sqlite") || name.hasSuffix(".db"), data.starts(with: Data("SQLite format 3".utf8)) {
            kind = .database
            let size = Int(data[data.startIndex + 16]) << 8 | Int(data[data.startIndex + 17])
            pageSize = size == 1 ? 65536 : size
        } else {
            kind = .plain
            pageSize = 4096
        }
    }

    func place(at offset: Int) -> String {
        switch kind {
        case .plain: return "plain file"
        case .database:
            let page = offset / pageSize + 1
            return "db page \(page): \(owners[page] ?? "free page")"
        case .log:
            guard offset >= 32 else { return "log header" }
            let frame = (offset - 32) / (pageSize + 24)
            let start = 32 + frame * (pageSize + 24)
            let page = Int(Self.bigEndian(data, at: start))
            return "log frame \(frame + 1) of db page \(page): \(owners[page] ?? "free page")"
        }
    }

    /// A sibling database file as a whole: for a log, its database file with the log next to it.
    private var databaseCopy: URL {
        kind == .log ? URL(fileURLWithPath: String(file.path.dropLast(4))) : file
    }

    private static func bigEndian(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(data[data.startIndex + offset + $1]) }
    }

    /// The owner of each page of a database, from the `dbstat` table of a copy opened next to nowhere near the store.
    private static func owners(of database: URL) -> [Int: String] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "erase-canary-owners-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owners: [Int: String]? = try? {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: "copy.sqlite")
            try FileManager.default.copyItem(at: database, to: copy)
            let log = URL(fileURLWithPath: database.path + "-wal")
            if FileManager.default.fileExists(atPath: log.path) {
                try FileManager.default.copyItem(at: log, to: folder.appending(path: "copy.sqlite-wal"))
            }
            return try DatabaseQueue(path: copy.path).read { db in
                Dictionary(
                    try Row.fetchAll(db, sql: "SELECT pageno, name FROM dbstat").map {
                        (Int($0["pageno"] as Int64), $0["name"] as String)
                    },
                    uniquingKeysWith: { first, _ in first })
            }
        }()
        return owners ?? [:]
    }
}
