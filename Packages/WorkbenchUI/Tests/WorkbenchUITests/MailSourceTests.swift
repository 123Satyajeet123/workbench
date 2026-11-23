import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor
@Suite struct MailSourceTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private func open(_ label: String, thread: String, message: String, text: String, in store: Store) throws {
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/\(label)/\(thread)",
            label: label, threadId: thread, messageId: message)
        let sent = MailMessage(context: context, sender: "Ana <ana@acme.example>", subject: "Acme", text: text)
        _ = PageHost.answer(try JSONEncoder().encode(sent), store: store, browser: "com.brave.Browser")
    }

    @Test func namingALabelSwitchesMailOnForThatLabelOnly() throws {
        let store = try scratchStore(clock: { noon })
        let capture = try CaptureService(store: store)
        let source = MailSource(store: store, capture: capture)
        #expect(!source.isReady && source.labels.isEmpty && source.grantLabels.isEmpty)

        try source.choose("  ")
        #expect(source.labels == ["Deals"] && source.isReady, "no name means the default label")
        #expect(try store.currentPolicy().isEnabled(.mail))
        try source.choose("Hot deals")
        #expect(source.labels == ["Hot deals"], "one label at a time")
        #expect(try store.currentPolicy().allowList[.mail] == ["Hot deals"])
        try capture.update { $0.switches[.mail] = false }
        #expect(!source.isReady, "switched off in Settings means nothing is read")
    }

    @Test func thePersonIsToldWhenTheGmailReaderFoundItsPageChangedAndWhenItReadsAgain() throws {
        let store = try scratchStore(clock: { noon })
        let source = MailSource(store: store, capture: try CaptureService(store: store))
        let day = WorkDay(containing: noon)
        try source.refresh(on: day)
        #expect(source.readerProblem == nil)

        _ = PageHost.answer(
            Data(#"{"type":"adapter_state","site":"Gmail","stale":true}"#.utf8), store: store, browser: nil)
        try source.refresh(on: day)
        #expect(source.readerProblem == "Workbench cannot read Gmail now: the page changed.")

        _ = PageHost.answer(
            Data(#"{"type":"adapter_state","site":"Slack","stale":true}"#.utf8), store: store, browser: nil)
        _ = PageHost.answer(
            Data(#"{"type":"adapter_state","site":"Gmail","stale":false}"#.utf8), store: store, browser: nil)
        try source.refresh(on: day)
        #expect(source.readerProblem == nil, "a stale Slack reader is not a Gmail problem")
    }

    @Test func dealIntakeRatesAMailPitchByTheCriteriaAndReadsNoOtherLabel() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        let source = MailSource(store: store, capture: capture)
        let intake = HelperModel(
            machine: machine, source: source, store: store,
            makeModel: { _ in RecordedModel(ScriptedModel("{\"items\":[]}"), store: store) }, notifier: FakeNotifier())
        #expect(machine.spec.source == .mail && !intake.isReady)
        await intake.read()

        try source.choose("Deals")
        try open(
            "Deals", thread: "T1", message: "m1",
            text: "Acme (fintech) is raising a 2M seed, 40k MRR. Deck attached.", in: store)
        try open("Personal", thread: "T2", message: "m2", text: "Dinner on Friday? Bring the cat photos.", in: store)
        let mailLine = try #require(try store.queries.mailParts(from: .distantPast, to: .distantFuture).first?.id)
        let reply = """
            {"items":[{"company":"Acme","sector":"fintech","stage":"seed","from":"Ana","cite":\(mailLine),
            "quote":"Acme (fintech) is raising a 2M seed",
            "r_stage":"yes","r_stage_quote":"raising a 2M seed","r_stage_reason":"A seed round.",
            "r_traction":"yes","r_traction_quote":"40k MRR","r_traction_reason":"Revenue is stated."}]}
            """
        let scripted = ScriptedModel(reply)
        let reading = HelperModel(
            machine: machine, source: source, store: store,
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())
        reading.reload()
        #expect(source.mailReading.parts.count == 1 && source.threadsOpened == 1)
        await reading.read()

        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains("Ana <ana@acme.example> — Acme: Acme (fintech) is raising a 2M seed"))
        #expect(!input.contains("cat photos"), "mail in another label never reaches the model")
        #expect(reading.items.map { $0["company"] } == ["Acme"])
        #expect(reading.items.first?["rating"] == "hot", "code rates it from the rule readings")
        #expect(reading.spec.triage(of: try #require(reading.items.first))?.needsReview == false)
        #expect(reading.phase == .read(kept: 1, dropped: 0))
    }

    @Test func aReadAfterTheLabelIsSwitchedOffReadsNothing() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let source = MailSource(store: store, capture: capture)
        try source.choose("Deals")
        try open("Deals", thread: "T1", message: "m1", text: "Acme raises a seed", in: store)
        let scripted = ScriptedModel("{\"items\":[]}")
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        let intake = HelperModel(
            machine: machine, source: source, store: store,
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())
        try capture.update { $0.switches[.mail] = false }
        intake.reload()
        await intake.read()
        #expect(scripted.inputs.withLock { $0.isEmpty })
        #expect(source.mailReading.parts.isEmpty)
    }
}
