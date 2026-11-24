import Foundation
import Observation
import WorkbenchCore

/// Where each fact the app shows is filed: its home, and the place a model proposed that waits for the person. A model
/// only proposes; only the person's confirm or move changes a home (research 86, Decision 3).
@Observable
final class FactHomes {
    struct Standing: Equatable {
        var home: WorkObject?
        var proposed: WorkObject?

        /// The place the fact is filed to, or waits to be filed to.
        var place: WorkObject? { proposed ?? home }
    }

    private(set) var standings: [ItemID: Standing] = [:]
    /// The places a fact may be filed under.
    private(set) var places: [WorkObject] = []
    /// What went wrong for a fact, said where the fact shows its home.
    private(set) var problems: [ItemID: String] = [:]

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let homesChanged: () -> Void

    /// `homesChanged` runs after the person moves or confirms a home, so the pages that list a place's facts read again.
    init(store: Store, homesChanged: @escaping () -> Void = {}) {
        self.store = store
        self.homesChanged = homesChanged
        readPlaces()
    }

    func read(_ item: ItemID) {
        attempt("read where it is filed", on: [item]) { try readStanding(of: item) }
    }

    /// Reads the places and every fact read so far again: a reading may propose new homes.
    func refresh() {
        readPlaces()
        for item in standings.keys { read(item) }
    }

    /// The person agrees with the place a model proposed.
    func confirm(_ item: ItemID, surface: MarkSurface) {
        act("confirm where it is filed", on: [item]) { try store.confirmHome(of: item, surface: surface) }
    }

    /// The person files the facts under `place`.
    func move(_ items: [ItemID], to place: WorkObjectID, surface: MarkSurface) {
        act("move it", on: items) {
            for item in items { try store.moveHome(of: item, into: place, surface: surface) }
        }
    }

    /// The places a move offers: every place but the one all `items` are filed to or wait for.
    func destinations(for items: [ItemID]) -> [WorkObject] {
        let filed = Set(items.map { standings[$0]?.place?.id })
        return places.filter { filed != [$0.id] }
    }

    private func readPlaces() {
        places = (try? store.queries.filingPlaces()) ?? places
    }

    private func readStanding(of item: ItemID) throws {
        standings[item] = Standing(
            home: try store.queries.home(of: item), proposed: try store.queries.proposedHome(of: item))
    }

    private func act(_ step: String, on items: [ItemID], _ work: () throws -> Void) {
        attempt(step, on: items) {
            try work()
            for item in items { try readStanding(of: item) }
        }
        homesChanged()
    }

    private func attempt(_ step: String, on items: [ItemID], _ work: () throws -> Void) {
        do {
            try work()
            for item in items { problems[item] = nil }
        } catch {
            for item in items { problems[item] = "Could not \(step): \(error.localizedDescription)" }
        }
    }
}
