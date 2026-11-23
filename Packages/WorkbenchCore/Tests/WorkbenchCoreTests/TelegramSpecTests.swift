import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct TelegramSpecTests {
    @Test func telegramNeedsItsSwitchAndAChosenChat() {
        let ask = CaptureRequest(kind: .telegram, label: "-100123")
        #expect(CapturePolicy().authorize(ask, at: t0).denial == .sourceSwitchedOff)
        #expect(
            CapturePolicy(switches: [.telegram: true]).authorize(ask, at: t0).denial == .labelNotAllowed,
            "a Telegram switch with no chosen chat reads nothing")
        let chosen = CapturePolicy(switches: [.telegram: true], allowList: [.telegram: ["-100123"]])
        #expect(chosen.authorize(ask, at: t0).grant?.label == "-100123")
        #expect(chosen.authorize(CaptureRequest(kind: .telegram, label: "-100999"), at: t0).denial == .labelNotAllowed)
        #expect(
            CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["-100123"]]).authorize(ask, at: t0)
                .denial == .sourceSwitchedOff, "a WhatsApp choice never lets Telegram be read")
    }

    @Test func theTelegramTeamMachineKeepsPipsFactsAndReadsTelegram() {
        let telegram = HelperSpec.teamTelegram
        #expect(telegram.source.kind == .telegram)
        #expect(telegram.task != HelperSpec.team.task)
        #expect(telegram.fields == HelperSpec.team.fields && telegram.lifecycle == HelperSpec.team.lifecycle)
        #expect(telegram.update(toward: .teamTelegram) == nil)
        #expect(telegram.source.lines.contains("Telegram group") && !telegram.source.lines.contains("WhatsApp"))
    }
}
