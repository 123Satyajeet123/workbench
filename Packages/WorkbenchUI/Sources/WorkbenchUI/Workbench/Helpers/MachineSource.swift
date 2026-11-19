import Foundation
import WorkbenchCore

/// Where a machine reads from. The model asks a source only these questions. What a source adds, such as a chat to
/// choose or sites to name, stays on its own type and its own views.
protocol MachineSource: AnyObject {
    /// The part of the source this machine reads, as a store scope; empty when the machine reads the whole source.
    var scope: String { get }
    /// A machine reads nothing until its source says it has what it needs.
    var isReady: Bool { get }
    /// The named sets of people or things the source knows now, as far as they are known.
    var context: [String: [String]] { get }
    /// The labels the capture policy must grant before a read; nil is the source as a whole.
    var grantLabels: [String?] { get }

    /// Loads what the source can show about `day` without reading it with a model.
    func refresh(on day: WorkDay) throws
    /// The numbered lines of `day` that a reading sends to the model.
    func evidence(on day: WorkDay) async throws -> EvidenceSet
}

extension MachineSource {
    var context: [String: [String]] { [:] }
    var grantLabels: [String?] { [scope.isEmpty ? nil : scope] }
    func refresh(on day: WorkDay) throws {}
}
