import Foundation

/// A machine a person can make: a spec with a default name and a line on what it does. The built-in ones are data in
/// `BuiltInTemplates.swift`.
public struct MachineTemplate: Sendable, Identifiable, Hashable {
    public let spec: HelperSpec
    public let name: String
    /// What kind of machine it is, under its name.
    public let role: String
    public let detail: String
    /// The hue of the machine's face, from 0 to 1; nil gives each machine a hue of its own.
    public var hue: Double?

    public var id: String { spec.task }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public static func of(id: String) -> MachineTemplate? { all.first { $0.id == id } }
    public static func of(_ machine: Machine) -> MachineTemplate? { machine.template.flatMap(of(id:)) }
}

extension HelperSpec {
    /// A machine stored before feeds and claim types were data has neither. It reads the lists of its template.
    func filling(from template: HelperSpec?) -> HelperSpec {
        var spec = self
        spec.feeds = feeds ?? template?.feeds
        spec.claimTypes = claimTypes ?? template?.claimTypes
        return spec
    }
}
