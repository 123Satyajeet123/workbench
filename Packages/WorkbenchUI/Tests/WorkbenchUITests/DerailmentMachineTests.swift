import AppKit
import CaptureService
import Foundation
import SwiftUI
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Sentinel, the off-track watch: it follows Pip's open facts and tells the founder what went wrong.
@Suite struct DerailmentMachineTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private static let pipKey = "You keep the facts of a founder's company"
    private static let sentinelKey = "You watch a founder's work for what is going off track"
    private static let overdue =
        #"{"items":[{"kind":"overdue","project":"Login API","severity":"act","next":"Ask Asha for the login API","reason":"Asked for yesterday, no sign it shipped","facts":["F1"],"lines":[],"quote":"login API done"}]}"#

    private struct Setup {
        let pip: HelperModel
        let sentinel: HelperModel
        let model: KeyedModel
        let notifier: FakeNotifier
        let container: URL
        let clock: TestClock
        let store: Store
    }

    /// Pip read yesterday and holds one open commitment; Sentinel follows it. The clock is then moved to today.
    private func setup() async throws -> Setup {
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        let container = try whatsApp(at: noon)
        let model = KeyedModel([
            Self.pipKey:
                #"{"items":[{"kind":"commitment","text":"Ship the login API","person":"Asha","project":"Login API","eta":"","asks":"team","stance":"said","cite":11,"quote":"login API done"}],"closes":[]}"#,
            Self.sentinelKey: Self.overdue,
        ])
        let notifier = FakeNotifier()
        func helper(_ spec: HelperSpec, _ name: String) throws -> HelperModel {
            let machine = try store.createMachine(from: spec, name: name)
            let source = try WhatsAppSource(
                store: store, capture: try CaptureService(store: store), task: machine.task, founder: { "Kabir" },
                container: container)
            try source.loadGroups()
            try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
            return HelperModel(
                machine: machine, source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
                notifier: notifier)
        }
        let pip = try helper(.team, "Pip")
        await pip.read()
        var followingPip = HelperSpec.derailment
        followingPip.follows = pip.spec.task
        let sentinel = try helper(followingPip, "Sentinel")
        clock.set(noon.addingTimeInterval(86_400))
        try addMessage(40, "lunch at two", at: clock.now, to: container)
        return Setup(
            pip: pip, sentinel: sentinel, model: model, notifier: notifier, container: container, clock: clock,
            store: store)
    }

    @Test func aCommitmentFromYesterdayIsFlaggedOverdueOnceAndTheAlertComesOnlyForTheNewFinding() async throws {
        let s = try await setup()
        #expect(s.pip.open.map { $0["text"] } == ["Ship the login API"])
        s.sentinel.watch = WatchSchedule(isOn: true, everyMinutes: 60, fromHour: 9, untilHour: 22)
        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.readIfDue()

        let input = try #require(s.model.inputs.withLock { $0.last })
        #expect(input.contains("Still open from earlier days:\nF1 ("), "yesterday's commitment is shown by handle")
        #expect(input.contains("kind=commitment"))
        let found = try #require(s.sentinel.items.first)
        #expect(s.sentinel.items.count == 1 && found["kind"] == "overdue" && found["severity"] == "act")
        let pipFact = try #require(s.pip.open.first?.id)
        #expect(found["facts"] == "\(pipFact)")
        #expect(s.notifier.posted.map(\.body) == ["Ask Asha for the login API"], "act is the bad tone: one alert")

        s.clock.set(s.clock.now.addingTimeInterval(3700))
        try addMessage(41, "still nothing", at: s.clock.now, to: s.container)
        await s.sentinel.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 3, "Pip once, Sentinel twice")
        #expect(s.sentinel.items.count == 1, "the same reply a second time adds nothing")
        #expect(s.notifier.posted.count == 1, "and tells the founder nothing")
    }

    @Test func aReadingThatNamesAnotherFactIsAddedAndAFactTheFounderRejectedStaysTold() async throws {
        let s = try await setup()
        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.read()
        s.sentinel.mark(try #require(s.sentinel.items.first), as: .rejected)
        try addMessage(41, "still nothing", at: s.clock.now.addingTimeInterval(60), to: s.container)
        await s.sentinel.read()
        #expect(s.sentinel.items.map(\.state) == [.rejected], "a rejected finding is not raised again")
    }

    private func watching(_ s: Setup) {
        s.sentinel.watch = WatchSchedule(isOn: true, everyMinutes: 60, fromHour: 9, untilHour: 22)
        s.sentinel.show(WorkDay(containing: s.clock.now))
    }

    @Test func aDayWithNoMessagesIsReadOnceWhileTheFollowedMachineHasOpenFacts() async throws {
        let s = try await setup()
        s.clock.set(noon.addingTimeInterval(2 * 86_400))
        watching(s)
        await s.sentinel.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 2, "Pip once, Sentinel once, though nobody wrote")
        let input = try #require(s.model.inputs.withLock { $0.last })
        #expect(input.contains("Work day: \(WorkDay(containing: s.clock.now))") && input.contains("F1 ("))
        #expect(s.sentinel.items.count == 1 && s.sentinel.items.first?["kind"] == "overdue")

        s.clock.set(s.clock.now.addingTimeInterval(3700))
        await s.sentinel.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 2, "the same quiet day is not read twice")

        s.clock.set(noon.addingTimeInterval(3 * 86_400))
        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 3, "the next quiet day is read again")
    }

    @Test func aQuietDayRunsNoModelWhenTheFollowedMachineHasNothingOpen() async throws {
        let s = try await setup()
        s.pip.close(try #require(s.pip.open.first), as: "kept")
        s.clock.set(noon.addingTimeInterval(2 * 86_400))
        watching(s)
        await s.sentinel.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 1, "only Pip's own first reading ran")
        #expect(s.sentinel.items.isEmpty)
    }

    @Test func aReadingOfAPastDayIsGivenTheFactsThatWereOpenThenEvenIfClosedSince() async throws {
        let s = try await setup()
        s.pip.close(try #require(s.pip.open.first), as: "kept")
        s.sentinel.show(WorkDay(containing: noon))
        await s.sentinel.read()
        let past = try #require(s.model.inputs.withLock { $0.last })
        #expect(past.contains("Still open from earlier days:\nF1 ("), "it was open on that day")

        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.read()
        #expect(try #require(s.model.inputs.withLock { $0.last }).contains("Still open") == false, "closed by today")
    }

    @Test func aTrialOfAMachineThatFollowsIsGivenTheFollowedFactsOpenOnTheDayAndKeepsItsFindings() async throws {
        let s = try await setup()
        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.read()
        let today = WorkDay(containing: s.clock.now)
        try #require(EvalSplit(today) == .dev, "the fixture day must be a training day")

        await s.sentinel.startTrial(brief: HelperSpec.derailment.brief + " Be brief.")
        let input = try #require(s.model.inputs.withLock { $0.last })
        #expect(input.contains("Still open from earlier days:\nF1 ("))
        let trial = try #require(s.sentinel.trial)
        #expect(trial.result.same == 1, "the trial kept the finding the live version made")
        #expect(trial.result.added.isEmpty && trial.result.dropped.isEmpty)
    }

    @Test func aTrialOfAMachineWithALifecycleCannotCloseTheLiveMachinesItems() async throws {
        let s = try await setup()
        let yesterday = WorkDay(containing: noon)
        try #require(EvalSplit(yesterday) == .dev, "the fixture day must be a training day")
        s.clock.set(noon.addingTimeInterval(3600))
        let live = try #require(s.pip.open.first)
        s.model.replies.withLock {
            $0[Self.pipKey] =
                #"{"items":[],"closes":[{"handle":"F1","outcome":"kept","cite":11,"quote":"login API done"}]}"#
        }
        s.pip.show(yesterday)
        await s.pip.startTrial(brief: HelperSpec.team.brief + " Be brief.")
        let input = try #require(s.model.inputs.withLock { $0.last })
        #expect(input.contains("Still open from earlier days:"), "the trial sees what was open")
        #expect(try s.store.queries.openItems(readBy: s.pip.spec).map(\.id) == [live.id], "the live item stays open")
    }

    @Test func aMachineThatFollowsIsCreatedOnlyWhenAMachineWithALifecycleExists() throws {
        let store = try scratchStore()
        try store.seedMachines([(.timeline, "Timeline")])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        #expect(crew.followable == nil)
        #expect(crew.create(from: .derailment, name: "") == nil)
        #expect(crew.problem == Crew.nothingToFollow && crew.machines.count == 1)

        let pipID = try #require(crew.create(from: .team, name: "Pip"))
        let pip = try #require(crew.helper(id: pipID))
        #expect(crew.followable === pip)
        let sentinelID = try #require(crew.create(from: .derailment, name: ""))
        let sentinel = try #require(crew.helper(id: sentinelID))
        #expect(sentinel.name == "Sentinel" && sentinel.spec.follows == pip.spec.task)
        #expect(MachineTemplate.of(sentinel.machine)?.role == "Off-track watch")
    }

    @Test func sentinelFollowsPipFromAStoreThatStartsWithTheSeededMachines() throws {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let sentinelID = try #require(crew.create(from: .derailment, name: ""))
        let sentinel = try #require(crew.helper(id: sentinelID))
        #expect(crew.followable?.spec.task == HelperSpec.team.task)
        #expect(sentinel.spec.follows == HelperSpec.team.task, "the first machine with a lifecycle is Pip")
    }

    @Test func theFindingsPageGroupsBySeverityAndShowsTheNextStep() async throws {
        let s = try await setup()
        s.sentinel.show(WorkDay(containing: s.clock.now))
        await s.sentinel.read()
        let crew = Crew(store: s.store, capture: try CaptureService(store: s.store), founder: { "" })
        let deals = DealsModel(
            store: s.store, catalog: TeamCatalogModel(store: s.store, crew: crew, author: { "Kabir" }))
        let view = ItemGroups(model: s.sentinel, field: "severity")
            .environment(ActionsModel(store: s.store, founder: { "" })).environment(deals).environment(crew)
            .padding(24).frame(width: 640).background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let file = FileManager.default.temporaryDirectory.appending(path: "sentinel-findings.png")
        try png.write(to: file)
        #expect(png.count > 2000)
    }
}
