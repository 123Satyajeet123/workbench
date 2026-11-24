import CaptureService
import Foundation
import Observation
import WorkbenchCore

/// The Gmail threads the investor opened inside the label they named. Naming the label is the consent: mail in no
/// other label is kept or read. The text comes from the browser extension, and the decks' text from their PDFs.
@Observable
final class MailSource: MachineSource {
    static let defaultLabel = "Deals"

    private(set) var mailReading: (parts: [MailPart], leftOut: Int) = ([], 0)
    /// Threads of the named labels opened on the day, as last refreshed. Threads never opened cannot be known.
    private(set) var threadsOpened = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService

    init(store: Store, capture: CaptureService) {
        self.store = store
        self.capture = capture
    }

    let scope = ""

    /// The labels mail may be read in; empty while mail is off.
    var labels: [String] { capture.policy.isEnabled(.mail) ? (capture.policy.allowList[.mail] ?? []).sorted() : [] }
    var isReady: Bool { !labels.isEmpty }
    var standing: SourceStanding {
        if isReady { .ready } else if capture.policy.isEnabled(.mail) { .nothingChosen } else { .off }
    }
    var picks: String? { "a label" }
    var grantLabels: [String?] { labels }
    var chosenSummary: String? { isReady ? "Gmail · " + labels.joined(separator: ", ") : nil }
    var hasNothingToRead: Bool { mailReading.parts.isEmpty }

    /// Switches mail on for one label, as typed in Gmail. An empty name is the default label. The one label replaces
    /// any earlier one.
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
