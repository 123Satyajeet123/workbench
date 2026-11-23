import Foundation
import LocalSources
import Testing
import WorkbenchCore

@testable import TelegramReader

private struct FixedPolicy: CapturePolicyProvider {
    var policy: CapturePolicy
    func currentPolicy() async throws -> CapturePolicy { policy }
}

private final class Recorded: TelegramService, @unchecked Sendable {
    var people: [TelegramMember] = []
    var history: [TelegramMessage] = []
    private(set) var asked: [Int64] = []

    func connect(_ keys: TelegramKeys, policy: CapturePolicy, onChange: @escaping @Sendable (TelegramLogin) -> Void)
        throws
    {}
    func checkPassword(_ password: String) async throws {}
    func groups() async throws -> [TelegramChat] { [] }
    func members(of chat: Int64) async throws -> [TelegramMember] { people }
    func messages(in chat: Int64, from start: Date, to end: Date) async throws -> [TelegramMessage] {
        asked.append(chat)
        return history
    }
    func signOut() async throws {}
}

private let group: Int64 = -100_123
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let end = start.addingTimeInterval(86_400)
private let asha = TelegramMember(id: 1, name: "Asha")
private let ravi = TelegramMember(id: 2, name: "Ravi")
private let chosen = FixedPolicy(
    policy: CapturePolicy(switches: [.telegram: true], allowList: [.telegram: [String(group)]]))

private func message(_ id: Int64, at offset: TimeInterval, chat: Int64 = group) -> TelegramMessage {
    TelegramMessage(
        id: id, chat: chat, date: start.addingTimeInterval(offset), kind: .text, sender: "Asha", isOutgoing: false,
        text: "line \(id)")
}

@Suite struct TelegramReaderTests {
    @Test func aChosenGroupWhoseMembersAllAgreedGivesThatDaysMessagesInOrder() async throws {
        let service = Recorded()
        service.people = [asha, ravi]
        service.history = [message(3, at: 500), message(1, at: -10), message(2, at: 100), message(4, at: 86_400)]
        service.history.append(message(5, at: 200, chat: -100_999))
        let reader = TelegramChatReader(service: service, chat: group, agreed: [1, 2], policy: chosen)
        let read = try await reader.read(from: start, to: end)
        #expect(read.messages.map(\.id) == [2, 3])
        #expect(read.members == [asha, ravi])
    }

    @Test func aNewcomerWhoHasNotAgreedStopsTheReadBeforeAnyMessageIsFetched() async throws {
        let service = Recorded()
        service.people = [asha, ravi]
        service.history = [message(1, at: 10)]
        let reader = TelegramChatReader(service: service, chat: group, agreed: [1], policy: chosen)
        await #expect(throws: TelegramConsentMissing(people: [ravi])) { try await reader.read(from: start, to: end) }
        #expect(service.asked.isEmpty)
    }

    @Test func aGroupThatIsNotChosenOrATelegramSwitchedOffIsNeverRead() async throws {
        let service = Recorded()
        service.people = [asha]
        let other = TelegramChatReader(service: service, chat: -100_999, agreed: [1], policy: chosen)
        await #expect(throws: ReadError.denied(.labelNotAllowed)) { try await other.read(from: start, to: end) }
        var off = chosen
        off.policy.switches[.telegram] = false
        let switchedOff = TelegramChatReader(service: service, chat: group, agreed: [1], policy: off)
        await #expect(throws: ReadError.denied(.sourceSwitchedOff)) { try await switchedOff.read(from: start, to: end) }
        #expect(service.asked.isEmpty)
    }

    @Test func workbenchConnectsOnlyWithTelegramSwitchedOnAndCaptureOn() throws {
        #expect(throws: ReadError.denied(.sourceSwitchedOff)) { try TelegramGate.check(CapturePolicy()) }
        #expect(throws: ReadError.denied(.captureOff)) {
            try TelegramGate.check(CapturePolicy(mode: .off, switches: [.telegram: true]))
        }
        try TelegramGate.check(CapturePolicy(switches: [.telegram: true]))
    }
}
