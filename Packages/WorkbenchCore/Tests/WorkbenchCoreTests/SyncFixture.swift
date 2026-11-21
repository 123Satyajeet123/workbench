import Foundation

@testable import WorkbenchCore

/// A repeatable random source, so a failing shuffle can be run again.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// One Mac in a simulated team: its own keys and its own copy of the team folder.
struct Replica {
    let name: String
    let keys = PersonKeys()
    let team = temporaryDirectory()

    var transport: FolderTransport { FolderTransport(team: team) }
    var member: Roster.Member { .init(name: name, card: keys.card) }
    var files: [URL] {
        let root = team.appending(path: FolderTransport.subfolder)
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        return (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }
}

/// A team of simulated Macs. The first is the founder. Each has its own folder; `spread` copies files between folders
/// the way a cloud drive would: in any order, late, and more than once.
struct Cluster {
    let replicas: [Replica]

    var founder: Replica { replicas[0] }

    func sync(_ replica: Replica) -> TeamSync {
        TeamSync(transport: replica.transport, keys: replica.keys, name: replica.name, founder: founder.member)
    }

    func replica(_ name: String) -> Replica { replicas.first { $0.name == name }! }

    /// A team in which the founder has confirmed everyone, and every folder holds the whole roster.
    static func formed(_ names: [String]) throws -> Cluster {
        let cluster = Cluster(replicas: names.map(Replica.init))
        for replica in cluster.replicas.dropFirst() {
            try TeamSync.announce(name: replica.name, keys: replica.keys, on: replica.transport)
        }
        try cluster.spreadFully()
        let founder = cluster.sync(cluster.founder)
        for hello in try TeamSync.announcements(on: cluster.founder.transport)
        where hello.card != cluster.founder.keys.card {
            try founder.admit(hello)
        }
        try cluster.spreadFully()
        return cluster
    }

    func copy(
        _ files: [URL], from source: Replica, to target: Replica, duplicates: Bool = false
    ) throws {
        for file in files where !file.lastPathComponent.hasPrefix("copy-") {
            let relative = file.deletingLastPathComponent().lastPathComponent + "/" + file.lastPathComponent
            var copy = target.team.appending(path: FolderTransport.subfolder).appending(path: relative)
            try FileManager.default.createDirectory(
                at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.copyItem(at: file, to: copy)
            }
            if duplicates {
                copy = copy.deletingLastPathComponent().appending(path: "copy-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: copy)
            }
        }
    }

    func spreadFully() throws {
        for source in replicas {
            for target in replicas where target.name != source.name { try copy(source.files, from: source, to: target) }
        }
    }

    /// One round of gossip: each pair passes a random part of what the sender holds, in random order, some twice.
    func gossip(using random: inout SeededRandom) throws {
        for source in replicas {
            for target in replicas where target.name != source.name {
                let some = source.files.shuffled(using: &random).filter { _ in Bool.random(using: &random) }
                try copy(some, from: source, to: target, duplicates: Bool.random(using: &random))
            }
        }
    }
}

/// A plaintext work event by `author`, with a clock.
func workEvent(_ id: String, by author: String, clock: Int, text: String = "", audience: [String]? = nil) -> WorkEvent {
    var event = WorkEvent(id: id, object: "deal-1", author: author, clock: clock, at: t0, kind: .note, text: text)
    if let audience {
        let item = Item(
            task: "vc.deals-1", day: WorkDay(containing: t0), scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1,
            start: t0, end: t0, fields: ["company": "Acme"], quote: text, run: 1)
        let machine = Machine(id: 1, name: "Intake", template: "vc.deals", spec: .dealIntake, state: .active)
        event.kind = .link
        event.item = LinkedItem(machine: machine, item: item, audience: audience)
    }
    return event
}
