import Foundation
import WorkbenchCore

struct StateKey<Value> {
    let name: String
    private let write: (Value) throws -> String
    private let read: (String) throws -> Value?

    init(name: String, write: @escaping (Value) throws -> String, read: @escaping (String) throws -> Value?) {
        self.name = name
        self.write = write
        self.read = read
    }

    func load(from store: Store) throws -> Value? {
        try store.queries.state(forKey: name).flatMap(read)
    }

    func save(_ value: Value, to store: Store) throws {
        try store.saveState(try write(value), forKey: name)
    }

    func clear(in store: Store) throws {
        try store.saveState("", forKey: name)
    }
}

extension StateKey where Value: Codable {
    static func json(_ name: String) -> Self {
        StateKey(
            name: name,
            write: { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) },
            read: { $0.isEmpty ? nil : try JSONDecoder().decode(Value.self, from: Data($0.utf8)) })
    }
}

extension StateKey where Value: LosslessStringConvertible {
    static func text(_ name: String) -> Self {
        StateKey(name: name, write: { $0.description }, read: { Value($0) })
    }
}

extension StateKey where Value == Date {
    static func moment(_ name: String) -> Self {
        StateKey(name: name, write: { $0.ISO8601Format() }, read: { try? Date($0, strategy: .iso8601) })
    }
}

extension StateKey where Value == WorkDay {
    static func day(_ name: String) -> Self {
        StateKey(name: name, write: \.description, read: { WorkDay($0) })
    }
}

extension StateKey where Value == Bool {
    static func onOff(_ name: String) -> Self {
        StateKey(name: name, write: { $0 ? "on" : "off" }, read: { $0 == "on" })
    }
}
