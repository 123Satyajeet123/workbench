import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct AgreementModelTests {
    private func setUp() throws -> (Store, Crew, HelperModel, ScriptedModel) {
        let store = try scratchStore()
        let item: [String: Any] = [
            "company": "Zed", "sector": "x", "stage": "seed", "from": "", "cite": 1, "quote": "Zed Labs",
            "r_in": "yes", "r_in_quote": "Mumbai", "r_in_reason": "Mumbai is in India.", "r_team": "yes",
            "r_team_quote": "ex-Razorpay", "r_team_reason": "Sector experience.",
        ]
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: ["items": [item]]), as: UTF8.self)
        let model = ScriptedModel(reply)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        var spec = HelperSpec.dealIntake
        spec.criteria = Criteria(rules: [VCFixture.india, VCFixture.team])
        let id = try #require(crew.create(spec: spec, template: "vc.deals", name: "Deal intake"))
        return (store, crew, try #require(crew.helper(id: id)), model)
    }

    @Test func pastDealsAreKeptReadAndReportedAndStayOutOfEveryItemList() async throws {
        let (store, _, intake, model) = try setUp()
        intake.agreement.add(company: "Zed", text: "Zed Labs, Mumbai. ex-Razorpay founders.", url: "", call: "hot")
        intake.agreement.add(company: " ", text: "x", url: "", call: "hot")
        #expect(intake.agreement.deals.count == 1 && intake.agreement.waiting.count == 1)
        await intake.agreement.read()
        #expect(intake.agreement.waiting.isEmpty && intake.agreement.report.agreed == 1)
        #expect(try store.queries.state(forKey: "\(intake.spec.task).agreement")?.contains("Zed Labs, Mumbai") == true)
        #expect(try store.queries.items(of: intake.spec.task, since: intake.day.adding(days: -400)).isEmpty)
        #expect(model.inputs.withLock { $0.count } == 1)
    }

    @Test func theDealsSurviveARestart() async throws {
        let (store, _, intake, _) = try setUp()
        intake.agreement.add(company: "Zed", text: "Zed Labs", url: "https://x.test/deck", call: "warm")
        let again = HelperModel(
            machine: intake.machine, source: intake.source, store: store, makeModel: nil, notifier: FakeNotifier())
        #expect(
            again.agreement.deals.map(\.company) == ["Zed"] && again.agreement.deals.first?.url == "https://x.test/deck"
        )
    }

    @Test func deletingTheMachineDeletesItsHeldOutDeals() throws {
        let (store, _, intake, _) = try setUp()
        intake.agreement.add(company: "Zed", text: "Zed Labs", url: "", call: "cold")
        let key = "\(intake.spec.task).agreement"
        #expect(try store.queries.state(forKey: key) != nil)
        try store.setState(intake.machine, .deleted)
        #expect(try store.queries.state(forKey: key) == nil)
    }

    @Test func aRuleAddedLaterMakesReadDealsWaitForANewReadingAndAnUnchangedLimitDoesNot() async throws {
        let (_, crew, intake, _) = try setUp()
        intake.agreement.add(company: "Zed", text: "Zed Labs, Mumbai. ex-Razorpay founders.", url: "", call: "hot")
        await intake.agreement.read()
        var more = try #require(intake.spec.criteria)
        more.bestCut = 2
        crew.setCriteria(intake, more)
        #expect(intake.agreement.waiting.isEmpty, "a new threshold is applied by code to the same readings")
        #expect(intake.agreement.report.count(called: "hot", rated: "warm") == 1)
        crew.setCriteria(intake, more.adding(VCFixture.gambling))
        #expect(intake.agreement.waiting.count == 1, "a new rule has no reading yet")
    }
}
