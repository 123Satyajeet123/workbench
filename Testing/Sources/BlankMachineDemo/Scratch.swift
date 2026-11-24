import CaptureService
import Foundation
import Kernel
import LocalSources

@testable import WorkbenchCore
@testable import WorkbenchUI

private final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}

/// A scratch store with the app's own models over it, gone when `remove` runs. Nothing here touches the person's
/// store, a network or a window.
@MainActor
struct Scratch {
    let store: Store
    let crew: Crew
    let folder: URL
    let owner: PersonID

    init(named name: String) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "blank-machine-\(name)-\(UUID().uuidString)")
        store = try Store(directory: folder)
        owner = try PersonID("blank-machine-owner")
        crew = Crew(
            store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
            makeModel: nil, notifier: QuietNotifier(), owner: .success(owner),
            whatsAppContainer: folder.appending(path: "no-whatsapp"))
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }

    func today() -> TodayModel { TodayModel(store: store, crew: crew) }
}
