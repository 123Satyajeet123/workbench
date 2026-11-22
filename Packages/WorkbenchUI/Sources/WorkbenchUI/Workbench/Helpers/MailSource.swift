import CaptureService
import Foundation
import Observation
import WorkbenchCore

@Observable
final class MailSource: MachineSource {
    static let defaultLabel = "Deals"

    private(set) var mailReading: (parts: [MailPart], leftOut: Int) = ([], 0)
    private(set) var threadsOpened = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService

    init(store: Store, capture: CaptureService) {
        self.store = store
        self.capture = capture
    }

    let scope = ""

    var labels: [String] { capture.policy.isEnabled(.mail) ? (capture.policy.allowList[.mail] ?? []).sorted() : [] }
    var isReady: Bool { !labels.isEmpty }
    var grantLabels: [String?] { labels }

    func choose(_ typed: String) throws {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        try capture.update {
            $0.switches[.mail] = true
            $0.allowList[.mail] = [name.isEmpty ? Self.defaultLabel : name]
        }
    }

    func refresh(on day: WorkDay) throws {
        mailReading = try reading(on: day)
        threadsOpened = try labels.reduce(0) { $0 + (try store.queries.mailThreadsOpened(inLabel: $1)[day] ?? 0) }
    }

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        EvidenceSet(lines: try reading(on: day).parts.compactMap(\.evidence))
    }

    private func reading(on day: WorkDay) throws -> (parts: [MailPart], leftOut: Int) {
        MailPart.reading(try store.queries.mailParts(from: day.start, to: day.end), labels: Set(labels))
    }
}
