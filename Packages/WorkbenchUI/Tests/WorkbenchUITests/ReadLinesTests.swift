import CaptureService
import Foundation
import Kernel
import LocalSources
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Which lines a reading sends comes from the windows of finished runs, not from a number that only grows. And whose
/// lines they are comes from an owner that belongs to one person.
@Suite struct ReadLinesTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private let reply =
        #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#

    private struct Scene {
        let store: Store
        let source: WhatsAppSource

        func machine(_ model: any StructuredModel) -> HelperModel {
            let store = store
            return HelperModel(
                machine: .test(.team, "Pip"), source: source, store: store,
                makeModel: { _ in RecordedModel(model, store: store) })
        }
    }

    private func scene() throws -> Scene {
        let now = noon
        let store = try scratchStore(clock: { now })
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task,
            founder: { "Kabir" }, container: try whatsApp(at: noon))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        return Scene(store: store, source: source)
    }

    @Test func aSecondReadingSendsNothingBecauseARunHoldsEveryLine() async throws {
        let scene = try scene()
        let model = ScriptedModel(reply)
        let pip = scene.machine(model)
        await pip.read()
        await pip.read()
        #expect(model.inputs.withLock { $0.count } == 1)
        #expect(pip.phase == .upToDate)
    }

    @Test func afterDeleteEverythingAndAnotherIngestTheLinesAreSentAgain() async throws {
        let scene = try scene()
        let model = ScriptedModel(reply)
        let pip = scene.machine(model)
        await pip.read()
        try scene.store.delete(.everything(before: nil))
        await pip.read()
        let inputs = model.inputs.withLock { $0 }
        #expect(inputs.count == 2, "a store that starts again from number one does not hide its lines")
        #expect(inputs.last?.contains("Asha: login API done") == true)
        #expect(inputs.last?.contains("Read before") == false)
    }

    @Test func aRunThatFailedReadNothing() async throws {
        let scene = try scene()
        await scene.machine(ScriptedModel("not a reply")).read()
        let model = ScriptedModel(reply)
        await scene.machine(model).read()
        #expect(model.inputs.withLock { $0.first }?.contains("Asha: login API done") == true)
    }

    @Test func aRunCountsOnlyForTheTaskThatMadeIt() async throws {
        let scene = try scene()
        let other = HelperModel(
            machine: .test(.team, "Other"), source: scene.source, store: scene.store,
            makeModel: { [store = scene.store] _ in RecordedModel(ScriptedModel(reply), store: store) })
        await other.read()
        let numbers = try scene.store.queries.currentLines(
            in: [teamJID], from: WorkDay(containing: noon).start, to: WorkDay(containing: noon).end
        ).map(\.number)
        #expect(try scene.store.queries.numbersRead(by: "someone else", among: numbers).isEmpty)
        #expect(try scene.store.queries.numbersRead(by: HelperSpec.team.task, among: numbers) == Set(numbers))
    }

    // MARK: Owner

    @Test func aSaveThatFailsLeavesTheLinesUnreadAndASavedReadingMarksThemRead() async throws {
        let scene = try scene()
        let store = scene.store
        let withdrawing = HookModel(reply) { try? store.savePolicy(CapturePolicy(switches: [.whatsapp: false])) }
        await scene.machine(withdrawing).read()
        #expect(try store.queries.runs().count == 1, "the model answered")
        try store.savePolicy(
            CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [teamJID]]))
        let model = ScriptedModel(reply)
        let pip = scene.machine(model)
        await pip.read()
        #expect(model.inputs.withLock { $0.first }?.contains("Asha: login API done") == true, "sent again")
        await pip.read()
        #expect(model.inputs.withLock { $0.count } == 1, "a saved reading marks its lines read")
    }

    // MARK: Owner

    @Test func eachInstallMintsItsOwnOwnerAndSoItsOwnSourceIds() throws {
        let first = try OwnerIdentity.person(secrets: MemorySecrets())
        let second = try OwnerIdentity.person(secrets: MemorySecrets())
        #expect(first != second)
        let one = try SourceDescriptor.whatsAppChat.sourceID(owner: first)
        let two = try SourceDescriptor.whatsAppChat.sourceID(owner: second)
        #expect(one != two, "two founders who read the same group do not share a source id")
    }

    @Test func oneInstallKeepsItsOwnerAcrossRestartsAndStoreDeletes() throws {
        let secrets = MemorySecrets()
        let owner = try OwnerIdentity.person(secrets: secrets)
        #expect(try OwnerIdentity.person(secrets: secrets) == owner, "a restart")
        _ = try scratchStore()
        #expect(try OwnerIdentity.person(secrets: secrets) == owner, "a new store, the old one deleted")
        #expect(owner.rawValue.hasPrefix("p-"))
        #expect(secrets.values.withLock { $0.count } == 1, "minted once")
    }

    @Test func aKeychainThatCannotAnswerNeverMintsOrOverwritesTheOwner() throws {
        let secrets = SecretsThatFailOnce()
        let kept = try OwnerIdentity.person(secrets: secrets.inner)
        secrets.failNext()
        #expect(throws: (any Error).self) { try OwnerIdentity.person(secrets: secrets) }
        #expect(secrets.inner.values.withLock { $0[OwnerIdentity.secretName] } == kept.rawValue, "not overwritten")
        #expect(secrets.creates == 0, "nothing was added")
        #expect(try OwnerIdentity.person(secrets: secrets) == kept, "asked again, the same person")
    }

    @Test func aSecondWriterThatWasFirstIsTheOwner() throws {
        let secrets = SecretsWithARacingWriter(winner: "p-the-first-one")
        #expect(try OwnerIdentity.person(secrets: secrets).rawValue == "p-the-first-one")
        #expect(secrets.values.withLock { $0[OwnerIdentity.secretName] } == "p-the-first-one")
    }

    @Test func anOwnerThatCannotBeKeptStopsTheStart() {
        #expect(throws: (any Error).self) { try OwnerIdentity.person(secrets: RefusingSecrets()) }
    }

    @Test func withoutAnOwnerTheAppStartsAndWhatsAppSaysWhy() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let owner = OwnerIdentity.result(secrets: RefusingSecrets())
        let capture = try CaptureService(store: store, owner: owner)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: noon))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let model = ScriptedModel(reply)
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
        await pip.read()
        #expect(pip.problem?.contains("could not open the name it keeps for you in the Keychain") == true)
        #expect(model.inputs.withLock { $0.isEmpty }, "nothing was read or sent")
    }
}

/// Runs `during` while it answers, as a model call that takes time lets the founder act.
private final class HookModel: StructuredModel, Sendable {
    let name = "hook"
    private let inner: ScriptedModel
    private let during: @Sendable () -> Void

    init(_ reply: String, during: @escaping @Sendable () -> Void) {
        inner = ScriptedModel(reply)
        self.during = during
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        during()
        return try await inner.generate(type, schema: schema, instructions: instructions, input: input)
    }
}

/// A Keychain that answers with an error once when told to, as one that asks for access and is refused.
private final class SecretsThatFailOnce: SecretStore, Sendable {
    struct Refused: Error {}
    let inner = MemorySecrets()
    private let failing = Mutex(false)
    private let created = Mutex(0)
    var creates: Int { created.withLock { $0 } }
    func failNext() { failing.withLock { $0 = true } }
    func read(_ name: String) -> String? { nil }
    func lookup(_ name: String) throws -> String? {
        if failing.withLock({
            let was = $0
            $0 = false
            return was
        }) {
            throw Refused()
        }
        return try inner.lookup(name)
    }
    func create(_ value: String, as name: String) throws -> Bool {
        created.withLock { $0 += 1 }
        return try inner.create(value, as: name)
    }
    func save(_ value: String, as name: String) throws { try inner.save(value, as: name) }
    func remove(_ name: String) throws { try inner.remove(name) }
}

/// A Keychain where another writer stores an owner between the lookup and the add.
private final class SecretsWithARacingWriter: SecretStore, Sendable {
    let values = Mutex<[String: String]>([:])
    private let winner: String
    private let looked = Mutex(false)
    init(winner: String) { self.winner = winner }
    func read(_ name: String) -> String? { values.withLock { $0[name] } }
    func lookup(_ name: String) throws -> String? {
        if !looked.withLock({
            let was = $0
            $0 = true
            return was
        }) {
            return nil
        }
        return values.withLock { $0[name] }
    }
    func create(_ value: String, as name: String) throws -> Bool {
        values.withLock { $0[name] = winner }
        return false
    }
    func save(_ value: String, as name: String) throws { values.withLock { $0[name] = value } }
    func remove(_ name: String) throws {}
}

private struct RefusingSecrets: SecretStore {
    struct Refused: Error {}
    func read(_ name: String) -> String? { nil }
    func lookup(_ name: String) throws -> String? { nil }
    func create(_ value: String, as name: String) throws -> Bool { throw Refused() }
    func save(_ value: String, as name: String) throws { throw Refused() }
    func remove(_ name: String) throws {}
}
