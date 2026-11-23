import Foundation
import Testing
import WorkbenchCore

import struct Kernel.PersonID

@testable import CaptureService

/// Taking a Gmail label off the allow-list withdraws the consent for it: its lines go, no other label's.
@MainActor struct MailWithdrawalTests {
    private let owner = Result<PersonID, any Error>.success(try! PersonID("test-owner"))

    private func open(_ label: String, message: String, in store: Store) throws {
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/\(label)/T-\(label)",
            label: label, threadId: "T-\(label)", messageId: message)
        let mail = MailMessage(
            context: context, sender: "ana@acme.example", recipients: ["vc@fund.example"], text: "Words of \(label)")
        let reply = PageHost.answer(
            try JSONEncoder().encode(mail), store: store, browser: "com.brave.Browser", owner: owner)
        #expect(reply.kept)
    }

    private func service() throws -> (CaptureService, Store) {
        let store = try Store(
            directory: FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)"))
        try store.savePolicy(CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals", "Personal"]]))
        return (try CaptureService(store: store), store)
    }

    private func texts(_ store: Store) throws -> [String] {
        try store.queries.mailParts(from: .distantPast, to: .distantFuture).map(\.text)
    }

    @Test func removingALabelErasesItsMailLinesAndNoOtherLabels() throws {
        let (service, store) = try service()
        try open("Deals", message: "m1", in: store)
        try open("Personal", message: "m2", in: store)
        try service.update { $0.allowList[.mail]?.remove("Deals") }
        #expect(try texts(store) == ["Words of Personal"])
    }

    @Test func addingALabelOrChangingAnotherSettingErasesNoMail() throws {
        let (service, store) = try service()
        try open("Deals", message: "m1", in: store)
        try service.update { $0.allowList[.mail]?.insert("Hot") }
        try service.update { $0.switches[.screen] = true }
        #expect(try texts(store) == ["Words of Deals"])
    }
}
