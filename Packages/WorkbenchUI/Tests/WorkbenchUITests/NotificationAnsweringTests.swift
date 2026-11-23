import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A notifier that keeps which facts' notifications were taken out of Notification Centre.
private final class ClearingNotifier: Notifier {
    var cleared: [Int64] = []

    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
    func post(_ notice: FactNotice) async throws {}
    func removeDelivered(itemID: Int64) { cleared.append(itemID) }
}

@MainActor struct NotificationAnsweringTests {
    private struct World {
        let notifier: ClearingNotifier
        let today: TodayModel
        let navigation: Navigation
        let answering: NotificationAnswering
    }

    private func world() async throws -> World {
        let clock = TestClock(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let notifier = ClearingNotifier()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: notifier)
        try await TodaySample.populate(store: store, crew: crew, withSummaries: false)
        let today = TodayModel(store: store, crew: crew)
        let navigation = Navigation()
        let answering = NotificationAnswering(
            today: today, review: ReviewModel(store: store, crew: crew), crew: crew, navigation: navigation)
        return World(notifier: notifier, today: today, navigation: navigation, answering: answering)
    }

    @Test func doneOnANotificationClosesTheFactAndTakesTheNotificationAway() async throws {
        let world = try await world()
        let need = try #require(world.today.needs.first { $0.item.askedWith == nil })
        let id = try #require(need.item.id)

        world.answering.handle(.answer(NotificationAnswer(itemID: id, action: .done)))

        #expect(!world.today.needs.contains { $0.item.id == id }, "the fact still waits after Done")
        #expect(world.notifier.cleared == [id])
    }

    @Test func anAnswerForAFactThatNoLongerWaitsOnlyTakesTheNotificationAway() async throws {
        let world = try await world()
        let before = world.today.needs.map(\.item.id)

        world.answering.handle(.answer(NotificationAnswer(itemID: 987_654, action: .done)))

        #expect(world.today.needs.map(\.item.id) == before, "an answer for no waiting fact changed Today")
        #expect(world.notifier.cleared == [987_654])
    }

    @Test func aClickOnTheBodyAsksForThatFact() async throws {
        let world = try await world()
        world.answering.handle(.open(itemID: 42))
        #expect(world.navigation.requestedFact == 42)
        #expect(world.notifier.cleared.isEmpty)
    }
}
