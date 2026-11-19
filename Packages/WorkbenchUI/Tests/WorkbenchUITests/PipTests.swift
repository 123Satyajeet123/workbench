import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct PipTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private func makeTeam(
        reply: String = #"{"items":[]}"#, clock: TestClock? = nil, notifier: FakeNotifier = FakeNotifier()
    ) throws -> (HelperModel, Store, CaptureService, ScriptedModel, WhatsAppSource) {
        let now = noon
        let store = try clock.map { clock in try scratchStore(clock: { clock.now }) } ?? scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let model = ScriptedModel(reply)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: noon))
        let team = HelperModel(
            machine: .test(.team, "Pip"), source: .whatsapp(source), store: store,
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: notifier)
        return (team, store, capture, model, source)
    }

    private func at(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: noon)!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test func atNudgeTimePipReadsTodayAndNamesWhoHasNoUpdateOnce() async throws {
        let clock = TestClock(noon)
        let notifier = FakeNotifier()
        let (team, store, _, model, source) = try makeTeam(reply: oneEntry, clock: clock, notifier: notifier)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        await team.setNudge(on: true)
        await team.nudgeIfDue()
        #expect(notifier.posted.isEmpty)

        clock.set(at(hour: 21, minute: 45))
        await team.nudgeIfDue()
        #expect(notifier.posted.map(\.body) == ["No update today from Bharat."])
        #expect(model.inputs.withLock { $0.count } == 1)
        #expect(try store.queries.runs().count == 1)

        await team.nudgeIfDue()
        #expect(notifier.posted.count == 1)
    }

    @Test func aNudgeThatCannotReadSaysWhyAndDoesNotRetryEveryMinute() async throws {
        let clock = TestClock(noon)
        let notifier = FakeNotifier()
        let (team, _, capture, model, source) = try makeTeam(reply: oneEntry, clock: clock, notifier: notifier)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        await team.setNudge(on: true)
        try capture.update { $0.switches[.whatsapp] = false }
        clock.set(at(hour: 22))
        await team.nudgeIfDue()
        await team.nudgeIfDue()
        #expect(notifier.posted.count == 1)
        #expect(notifier.posted.first?.body.hasPrefix("Could not read the day") == true)
        #expect(model.inputs.withLock { $0.isEmpty })
    }

    @Test func theNudgeStaysOffWhenMacOSRefusesNotificationsAndSurvivesARestart() async throws {
        let notifier = FakeNotifier()
        notifier.access = .blocked
        let (team, store, capture, _, source) = try makeTeam(notifier: notifier)
        await team.setNudge(on: true)
        #expect(!team.nudge.isOn && team.notificationsBlocked)
        notifier.access = .failed("Notifications are not allowed for this application")
        await team.setNudge(on: true)
        #expect(!team.nudge.isOn)
        #expect(team.problem?.contains("not allowed for this application") == true)
        notifier.access = .allowed
        await team.setNudge(on: true)
        #expect(team.nudge.isOn && !team.notificationsBlocked)
        team.nudge.hour = 20
        let again = HelperModel(
            machine: .test(.team, "Pip"), source: .whatsapp(source), store: store, notifier: notifier)
        #expect(again.nudge == NudgeSchedule(isOn: true, hour: 20, minute: 30))
    }

    private let oneEntry = #"""
        {"items":[{"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API done"}]}
        """#

    @Test func listingGroupsAllowsNoChatAndChoosingOneAllowsOnlyThatOne() throws {
        let (team, store, capture, _, source) = try makeTeam()
        #expect(!capture.policy.isEnabled(.whatsapp))
        try source.loadGroups()
        #expect(source.groups.map(\.name) == ["Team", "Family"])
        #expect(capture.policy.authorize(CaptureRequest(kind: .whatsapp, label: teamJID), at: noon).grant == nil)
        try source.choose(try #require(source.groups.first))
        #expect(capture.policy.allowList[.whatsapp] == [teamJID])
        #expect(capture.policy.authorize(CaptureRequest(kind: .whatsapp, label: teamJID), at: noon).grant != nil)
        #expect(capture.policy.authorize(CaptureRequest(kind: .whatsapp, label: familyJID), at: noon).grant == nil)
        #expect(try store.currentPolicy() == capture.policy)
    }

    @Test func readingADaySendsOnlyTheTeamGroupAndStoresCheckedEntriesWithTheirRun() async throws {
        let reply = #"""
            {"items":[
              {"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API done"},
              {"person":"Asha","kind":"done","text":"Invented","eta":"","cite":11,"quote":"payments done"}]}
            """#
        let (team, store, _, model, source) = try makeTeam(reply: reply)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        await team.read()

        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Kabir (founder): ki aaj kya kiya?"))
        #expect(input.contains("Asha: login API done"))
        #expect(!input.contains("dinner"))
        #expect(team.items.map(\.quote) == ["login API done"])
        #expect(team.phase == .read(kept: 1, dropped: 1))
        #expect(source.members.map(\.name) == ["Asha", "Bharat"])
        let run = try #require(store.queries.runs().first)
        #expect(team.items.first?.run == run.id)
        #expect((run.kept, run.dropped) == (1, 1))
    }

    @Test func consentWithdrawnDuringTheReadStopsTheWrite() async throws {
        let (team, _, capture, _, source) = try makeTeam(reply: oneEntry)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        try capture.update { $0.switches[.whatsapp] = false }
        await team.read()
        #expect(team.items.isEmpty)
        #expect(team.problem?.hasPrefix("Could not read the day") == true)
    }

    @Test func aReadingAsksAboutOneOfItsItemsUntilItIsAnswered() async throws {
        let reply = #"""
            {"items":[
              {"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API done"},
              {"person":"Bharat","kind":"plan","text":"Payments","eta":"","cite":11,"quote":"login API"}]}
            """#
        let (team, store, _, _, source) = try makeTeam(reply: reply)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        #expect(team.question == nil)
        #expect(team.mood == .calm)
        await team.read()
        let question = try #require(team.question)
        #expect(team.mood == .asking)
        #expect(question.askedWith == 0.5)
        #expect(team.items.filter { $0.askedWith != nil }.count == 1)
        team.mark(question, as: .confirmed)
        #expect(team.question == nil)
        #expect(team.mood == .calm)
        #expect(team.trust != nil)
        #expect(try store.queries.quality().first?.audited == AuditEstimate(marks: 1, rightWeight: 2, weight: 2))
    }

    @Test func withNoGroupChosenNothingIsRead() async throws {
        let (team, store, _, model, source) = try makeTeam()
        await team.read()
        #expect(model.inputs.withLock { $0.isEmpty })
        #expect(team.items.isEmpty)
        #expect(try store.queries.runs().isEmpty)
    }

    /// Teams post screenshots as updates (measured: 20 of 20 photos in a day of the founder's group held text).
    @Test func aScreenshotIsReadOnThisMacAndCanBeQuotedAsAnUpdate() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let container = try whatsApp(at: noon)
        let photo = try addPhoto("OTA 4.1.11 installed", to: container, at: noon.addingTimeInterval(120))
        let model = ScriptedModel(
            #"{"items":[{"person":"Asha","kind":"done","text":"Installed the OTA","eta":"","cite":\#(photo),"quote":"OTA 4.1.11 installed"}]}"#
        )
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task, founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let team = HelperModel(
            machine: .test(.team, "Pip"), source: .whatsapp(source), store: store,
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        await team.read()
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Asha: [photo] OTA 4.1.11 installed"))
        #expect(team.items.map(\.quote) == ["OTA 4.1.11 installed"], "a quote from the photo passes the quote check")
    }

    /// Measured: macOS asked "access data from other apps" 7 times in one day. Opening Pip's page must not read
    /// WhatsApp; only a read or a live check may.
    @Test func openingThePageShowsTheLastKnownMembersWithoutReadingWhatsApp() async throws {
        let (_, store, capture, _, source) = try makeTeam()
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        try await source.loadMembers()
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-whatsapp-\(UUID().uuidString)")
        let reopened = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" }, container: missing)
        #expect(reopened.members.map(\.name) == ["Asha", "Bharat"])
        try await reopened.showMembers()
        await #expect(throws: (any Error).self) { try await reopened.loadMembers() }
    }
}

@Suite struct RunsModelTests {
    @Test func aReadAndItsMarksShowAsUsageAndPrecision() async throws {
        let store = try scratchStore()
        let capture = try CaptureService(store: store)
        let reply = #"""
            {"items":[{"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API done"}]}
            """#
        let model = ScriptedModel(reply)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: Date()))
        let team = HelperModel(
            machine: .test(.team, "Pip"), source: .whatsapp(source), store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        await team.read()
        team.mark(try #require(team.items.first), as: .confirmed)

        let runs = RunsModel(store: store)
        #expect(runs.runs.count == 1)
        #expect(runs.meter.today.tokens == 340)
        #expect(runs.meter.all.costUSD == 0.02)
        let quality = try #require(runs.quality.first)
        #expect(quality.all.precision == 1)
        #expect(quality.model == "scripted-1")
        #expect(runs.problem == nil)
    }
}
