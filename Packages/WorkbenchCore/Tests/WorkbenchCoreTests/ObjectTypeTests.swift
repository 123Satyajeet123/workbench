import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ObjectTypeTests {
    private let projectType = ObjectType(
        id: "project", noun: "project",
        fields: [FieldDef(id: "owner", label: "Owner", kind: .person), FieldDef(id: "due", label: "Due", kind: .date)],
        stages: [
            StageDef(id: "p.active", label: "Active", order: 1, meaning: .open),
            StageDef(id: "p.blocked", label: "Blocked", order: 2, meaning: .waiting),
            StageDef(id: "p.done", label: "Done", order: 3, meaning: .won),
            StageDef(id: "p.dropped", label: "Dropped", order: 4, meaning: .lost),
        ])

    private let hiringType = ObjectType(
        id: "hire", noun: "candidate",
        fields: [
            FieldDef(id: "role", label: "Role", kind: .text), FieldDef(id: "reason", label: "Reason", kind: .text),
            FieldDef(id: "revisit", label: "Revisit", kind: .date),
        ],
        stages: [
            StageDef(id: "h.applied", label: "Applied", order: 1, meaning: .open),
            StageDef(id: "h.interview", label: "Interview", order: 2, meaning: .open),
            StageDef(id: "h.hired", label: "Hired", order: 3, meaning: .won),
            StageDef(
                id: "h.rejected", label: "Rejected", order: 4, meaning: .watch, requires: ["reason"],
                after: [TimerRule(field: "revisit", defaultAfterDays: 365)]),
            StageDef(id: "h.withdrew", label: "Withdrew", order: 5, meaning: .lost),
        ])

    private func event(
        _ id: String, _ kind: WorkEvent.Kind, clock: Int, _ text: String = "", replaces: [String] = [],
        object: String = "o-1"
    ) -> WorkEvent {
        WorkEvent(
            id: id, object: object, author: "Asha", clock: clock, at: t0.addingTimeInterval(Double(clock) * 60),
            kind: kind, text: text, replaces: replaces)
    }

    private func fold(_ events: [WorkEvent], types: [ObjectType] = ObjectTypes.builtIn) throws -> WorkObject {
        try #require(
            WorkObject.fold(events, viewer: "Asha", type: { kind in types.first { $0.id == kind } ?? .unlisted(kind) })
                .first)
    }

    @Test func aFundPipelineATeamProjectAndAHiringPipelineAreEachOnlyData() throws {
        let types = [ObjectTypes.deal, projectType, hiringType]
        #expect(
            types.map { Set($0.stages.map(\.meaning)) } == [
                [.open, .waiting, .won, .watch], [.open, .waiting, .won, .lost], [.open, .won, .watch, .lost],
            ])
        for type in types {
            let created = event("c", .create, clock: 1, type.id)
            let entered = event("s", .stage, clock: 2, try #require(type.entryStage).id)
            let object = try fold([created, entered], types: types)
            #expect(object.type == type && object.stages == [type.entryStage?.id])
        }
    }

    @Test func noCodeOutsideTheBuiltInTypeDataNamesAStageOfTheFundPipeline() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let names = ["Action required", "Invested", "Rejected", "In conversation", "Founder meeting"]
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let naming = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.filter { file in
            let code = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            return code.contains { line in names.contains { line.contains($0) } }
        }
        #expect(naming.map(\.lastPathComponent) == ["DealV1.swift"])
    }

    @Test func oldDealEventsFoldToTheStageHeadsTheyAlwaysHad() throws {
        let events = [
            event("c", .create, clock: 1, "deal"), event("t", .title, clock: 2, "Acme"),
            event("s1", .stage, clock: 3, "Inbox"), event("s2", .stage, clock: 4, "In conversation", replaces: ["s1"]),
            event("s3", .stage, clock: 5, "Action required", replaces: ["s2"]),
            event("s4", .stage, clock: 6, "Founder meeting", replaces: ["s3"]),
            event("s5", .stage, clock: 7, "Passed", replaces: ["s4"]),
        ]
        for (count, heads, labels) in [
            (3, ["s1"], ["Inbox"]), (4, ["s2"], ["In conversation"]), (5, ["s3"], ["Action required"]),
            (6, ["s4"], ["Founder meeting"]),
        ] {
            let object = try fold(Array(events.prefix(count)))
            #expect(object.stageHeads == heads && object.stageLabels == labels)
        }
        let unknown = try fold(events)
        #expect(
            unknown.stageHeads == ["s5"] && unknown.stageLabels == ["Passed"], "unknown text is a retired open stage")
        #expect(unknown.meanings == [.open])
    }

    @Test func aNewStageEventHoldsTheIdAndAnOldOneHoldsTheLabelAndBothAreTheSameStage() throws {
        let object = try fold([
            event("c", .create, clock: 1, "deal"), event("a", .stage, clock: 2, "Screen"),
            event("b", .stage, clock: 2, "deal.screen"),
        ])
        #expect(object.stages == ["deal.screen"])
    }

    @Test func renamingAStageLabelLeavesHistoryAndStageHeadsAsTheyWere() throws {
        var renamed = ObjectTypes.deal
        renamed.version = 2
        renamed.stages = renamed.stages.map { stage in
            var stage = stage
            if stage.id == "deal.diligence" { stage.label = "Deep dive" }
            return stage
        }
        let events = [
            event("c", .create, clock: 1, "deal"), event("s1", .stage, clock: 2, "deal.diligence"),
        ]
        let before = try fold(events)
        let after = try fold(events, types: [try ObjectTypes.deal.revised(to: renamed)])
        #expect(before.history == after.history && before.stageHeads == after.stageHeads)
        #expect(
            before.stages == after.stages && before.stageLabels == ["Diligence"] && after.stageLabels == ["Deep dive"])
    }

    @Test func aStageWhoseMeaningChangesIsRefusedAndAStageIsRetiredNeverRemoved() throws {
        var next = ObjectTypes.deal
        next.version = 2
        next.stages = next.stages.map { stage in
            StageDef(
                id: stage.id, label: stage.label, order: stage.order,
                meaning: stage.id == "deal.invested" ? .lost : stage.meaning)
        }
        #expect(throws: ObjectTypeError.meaningChanged("deal.invested")) { try ObjectTypes.deal.revised(to: next) }

        var removed = ObjectTypes.deal
        removed.version = 2
        removed.stages.removeAll { $0.id == "deal.screen" }
        #expect(throws: ObjectTypeError.stageRemoved("deal.screen")) { try ObjectTypes.deal.revised(to: removed) }

        var retired = ObjectTypes.deal
        retired.version = 2
        retired.stages = retired.stages.map { stage in
            var stage = stage
            stage.retired = stage.id == "deal.screen"
            return stage
        }
        #expect(try ObjectTypes.deal.revised(to: retired).stage("deal.screen")?.retired == true)
        #expect(throws: ObjectTypeError.versionNotNext) { try ObjectTypes.deal.revised(to: ObjectTypes.deal) }
    }

    @Test func aMachineMoveMustCiteAFactForEveryRequiredFieldAndAPersonMoveIsFree() throws {
        let object = try fold([event("c", .create, clock: 1, "deal"), event("s1", .stage, clock: 2, "Screen")])
        let passed = "deal.rejected"
        #expect(throws: MoveRefusal.missingFacts(["reason"])) {
            try ObjectTypes.deal.move(object, to: passed, by: .machine)
        }
        #expect(throws: MoveRefusal.missingFacts(["reason"])) {
            try ObjectTypes.deal.move(object, to: passed, by: .machine, facts: ["reason": ""])
        }
        let allowed = try ObjectTypes.deal.move(object, to: passed, by: .machine, facts: ["reason": "fact-7"])
        #expect(allowed.stage == passed && allowed.replaces == ["s1"])
        #expect(allowed.after == [TimerRule(field: "revisit", defaultAfterDays: 180)])
        #expect(try ObjectTypes.deal.move(object, to: passed, by: .person).stage == passed)
        #expect(try ObjectTypes.deal.move(object, to: "deal.diligence", by: .machine).stage == "deal.diligence")
    }

    @Test func aMoveToAnUnknownOrRetiredStageIsRefused() throws {
        let object = try fold([event("c", .create, clock: 1, "deal")])
        #expect(throws: MoveRefusal.unknownStage("Passed")) {
            try ObjectTypes.deal.move(object, to: "Passed", by: .person)
        }
        var retired = ObjectTypes.deal
        retired.stages = retired.stages.map { stage in
            var stage = stage
            stage.retired = stage.id == "deal.screen"
            return stage
        }
        #expect(throws: MoveRefusal.retiredStage("deal.screen")) {
            try retired.move(object, to: "deal.screen", by: .person)
        }
    }

    @Test func twoMovesMadeFromTheSameStateBothStandUntilOneMoveReplacesBoth() throws {
        let start = [event("c", .create, clock: 1, "deal"), event("s1", .stage, clock: 2, "deal.screen")]
        let object = try fold(start)
        let first = try ObjectTypes.deal.move(object, to: "deal.diligence", by: .person)
        let second = try ObjectTypes.deal.move(object, to: "deal.decision", by: .person)
        let moves = [
            first.event(object: "o-1", author: "Kabir", clock: 3, at: t0),
            second.event(object: "o-1", author: "Asha", clock: 3, at: t0),
        ]
        let both = try fold(start + moves)
        #expect(both.stageLabels == ["Diligence", "Decision"])
        let settled = try ObjectTypes.deal.move(both, to: "deal.invested", by: .person)
        let one = try fold(start + moves + [settled.event(object: "o-1", author: "Asha", clock: 4, at: t0)])
        #expect(one.stageLabels == ["Invested"] && one.meanings == [.won])
    }

    @Test func aStoreHoldingTodaysDealEventsOpensAndFoldsToTheSameStageHeads() throws {
        let store = try makeStore()
        try store.append([
            event("c", .create, clock: 1, "deal"), event("t", .title, clock: 2, "Acme"),
            event("s1", .stage, clock: 3, "Inbox"), event("s2", .stage, clock: 4, "Diligence", replaces: ["s1"]),
        ])
        let deal = try #require(WorkObject.fold(try store.queries.workEvents(), viewer: "Asha").first)
        #expect(deal.stageHeads == ["s2"] && deal.stageLabels == ["Diligence"] && deal.kind == "deal")
    }
}
