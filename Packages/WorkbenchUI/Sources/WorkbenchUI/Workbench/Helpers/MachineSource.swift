import Foundation
import WorkbenchCore

protocol MachineSource: AnyObject {
    var scope: String { get }
    var isReady: Bool { get }
    var context: [String: [String]] { get }
    var grantLabels: [String?] { get }

    func refresh(on day: WorkDay) throws
    func evidence(on day: WorkDay) async throws -> EvidenceSet
}

extension MachineSource {
    var context: [String: [String]] { [:] }
    var grantLabels: [String?] { [scope.isEmpty ? nil : scope] }
    func refresh(on day: WorkDay) throws {}
}
