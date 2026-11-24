import Foundation
import LocalSources
import SwiftUI
import WorkbenchCore

/// Where a machine reads from. The model and the pages ask a source only these questions, and each source answers for
/// itself. What a source adds, such as a chat to choose or sites to name, stays on its own type and its own views.
protocol MachineSource: AnyObject {
    /// The part of the source this machine reads, as a store scope; empty when the machine reads the whole source.
    var scope: String { get }
    /// A machine reads nothing until its source says it has what it needs.
    var isReady: Bool { get }
    /// Why the source is not ready: its switch is off, or nothing is chosen for it to read.
    var standing: SourceStanding { get }
    /// What the person picks for the source to read, such as "chats"; nil for a source that reads without a pick.
    var picks: String? { get }
    var context: [String: [String]] { get }
    /// The labels the capture policy must grant before a read; nil is the source as a whole.
    var grantLabels: [String?] { get }
    /// The person opened the chooser again over what the source reads now.
    var isChanging: Bool { get }
    /// What the person chose for the source to read, in words; nil when nothing is chosen or nothing can be.
    var chosenSummary: String? { get }
    /// What the machine reads, in words.
    var reads: String { get }
    /// The containers the person chose, such as chats; empty for a source that reads no container of its own.
    var chosenContainers: [Container] { get }
    /// The day last refreshed has nothing to read.
    var hasNothingToRead: Bool { get }

    /// Loads what the source can show about `day` without reading it with a model.
    func refresh(on day: WorkDay) throws
    func evidence(on day: WorkDay) async throws -> EvidenceSet
    /// Reads in the source's own way, not by the day, with the model `model` makes, and returns how many facts it kept
    /// and dropped. Nil for a source that is read by the day.
    func ownRead(spec: HelperSpec, model: () throws -> RecordedModel) async throws -> (kept: Int, dropped: Int)?
    /// The lines around those a fact cites, `reach` on each side.
    func proof(of item: Item, reach: Int) async throws -> [ChatLine]
    /// Loads the people a page shows.
    func showMembers() async throws
    /// The people who can already read what the source read, for a share; nil when that is not known.
    func shareAudience() async throws -> [WhatsAppMember]?
    /// Stops reading one container the person chose, named by its id.
    func stopReading(container: String) throws

    /// Where the person chooses what the source reads; nil for a source with nothing to choose.
    func chooser(for model: HelperModel) -> AnyView?
    /// The source's own section at the top of the machine's readings.
    func pageSection(for model: HelperModel) -> AnyView?
    /// The machine's items, for a source that shows them its own way.
    func itemsView(for model: HelperModel) -> AnyView?
    /// The first rows of the machine's settings: what a reading sends, and what the person can change about the source.
    func settingsView(for model: HelperModel) -> AnyView
}

extension MachineSource {
    var standing: SourceStanding { isReady ? .ready : .nothingChosen }
    var context: [String: [String]] { [:] }
    var picks: String? { nil }
    var grantLabels: [String?] { [scope.isEmpty ? nil : scope] }
    var isChanging: Bool { false }
    var chosenSummary: String? { nil }
    var reads: String { chosenSummary ?? "Nothing chosen yet" }
    var chosenContainers: [Container] { [] }
    var hasNothingToRead: Bool { false }

    func refresh(on day: WorkDay) throws {}
    func ownRead(spec: HelperSpec, model: () throws -> RecordedModel) async throws -> (kept: Int, dropped: Int)? { nil }

    func proof(of item: Item, reach: Int) async throws -> [ChatLine] {
        ChatLine.around(item, in: try await evidence(on: item.day).lines, reach: Int64(reach))
    }

    func showMembers() async throws {}
    func shareAudience() async throws -> [WhatsAppMember]? { [] }
    func stopReading(container: String) throws {}

    func chooser(for model: HelperModel) -> AnyView? { nil }
    func pageSection(for model: HelperModel) -> AnyView? { nil }
    func itemsView(for model: HelperModel) -> AnyView? { nil }
    func settingsView(for model: HelperModel) -> AnyView { AnyView(ReadNote()) }
}
