import Foundation
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

enum Gates {
    static let extraction = """
        {"claims":[{"line":@raised $20 million@,"text":"Acme raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"},{"line":@serves 40 banks@,"text":"Acme serves 40 banks.","type":"customers","value":"40 banks","quote":"serves 40 banks"}]}
        """
    static let queries = #"{"queries":["Acme seed round"]}"#
    static let contradicted = #"{"verdict":"contradicted","page":1,"quote":"raised $11 Mn in its seed"}"#
    static let rating = """
        {"r_stage":"yes","r_stage_quote":"seed round in 2023","r_stage_reason":"It raised a seed round.","r_traction":"yes","r_traction_quote":"serves 40 banks","r_traction_reason":"It names 40 banks."}
        """
    static let deck = [
        "Acme Payroll: seed round deck", "Acme raised $20 million in its seed round in 2023.",
        "Acme serves 40 banks across India.",
    ]

    static let chatDeal = """
        {"items":[{"company":"Beta Pay","sector":"payments","stage":"seed","from":"Asha","r_stage":"yes","r_stage_quote":"raising a seed round","r_stage_reason":"It raises a seed round.","r_traction":"yes","r_traction_quote":"12 merchants pay us","r_traction_reason":"12 merchants pay.","cite":@Beta Pay@,"object":"","quote":"Beta Pay is raising a seed round"}]}
        """
    static let chatRating = """
        {"r_stage":"yes","r_stage_quote":"raising a seed round","r_stage_reason":"It raises a seed round.","r_traction":"yes","r_traction_quote":"12 merchants pay us","r_traction_reason":"12 merchants pay."}
        """
    static let madeUpRating = """
        {"r_stage":"yes","r_stage_quote":"closed a Series B in March","r_stage_reason":"A Series B.","r_traction":"yes","r_traction_quote":"serves 40 banks","r_traction_reason":"It names 40 banks."}
        """

    @MainActor static func run(png: URL) async {
        await gate("G1 a deal added by hand, with a file added to it, gets claims read and checked") { try await g1() }
        await gate("G2 a claim typed by hand is checked; the query writer gets the company and the claim only") {
            try await g2()
        }
        await gate("G3 any deal can be rated against the thesis; the why card cites its evidence; a mark overrides") {
            try await g3(png: png)
        }
        await gate("G4 \"Deals from chats\" is data only and shares the thesis answer in onboarding") { try await g4() }
        await gate("G7 the first look runs from data only, shows its cost first, and can be skipped") {
            try await g7(png: png)
        }
        await gate("G8 the watchlist question adds companies and imports deals by what their stage means") {
            try await g8(png: png)
        }
    }

    @MainActor static func g1() async throws {
        let desk = try Desk(replies: [extraction, queries, contradicted])
        defer { desk.close() }
        try desk.allow([.web: true])
        let deal = try desk.newDeal("Acme")
        check(deal.items.isEmpty, "the deal was added by hand: it has no linked item and no mail")

        await desk.claims.extract(from: deal)
        check(
            desk.claims.problems.text?.contains("no evidence") == true && desk.model.inputs.withLock { $0.isEmpty },
            "with no file the claims are not read, no model call is made, and it says why: "
                + "\"\(desk.claims.problems.text ?? "")\"")

        let file = try deckPDF(lines: deck, named: "acme-deck.pdf")
        desk.claims.addFile(file, to: deal)
        let lines = try desk.store.queries.evidence(of: deal, author: "Aditya")
        check(
            lines.count == 1 && lines[0].consent == Consent(kind: .dropped, label: "acme-deck.pdf"),
            "the PDF became \(lines.count) evidence line, written under the person's own act (\(lines.first?.line.prefix(60) ?? "")…)"
        )

        await desk.claims.extract(from: deal)
        let found = desk.claims.state(of: deal).claims
        check(
            found.map(\.text) == ["Acme raised $20 million.", "Acme serves 40 banks."],
            "claims read: \(found.map(\.text))")
        check(
            found.allSatisfy { $0.source == .dropped && $0.label != nil },
            "each claim has the source of its line (\(found.first?.source?.rawValue ?? "none")) and a known label")

        desk.claims.toggle(found[0], in: deal)
        await desk.claims.checkChosen(in: deal)
        let check1 = desk.claims.state(of: deal).checks.first
        check(
            check1?.verdict == .contradicted && check1?.quote == "raised $11 Mn in its seed",
            "the chosen claim was checked on the web: \(check1?.verdict.title ?? "none"), "
                + "\"\(check1?.quote ?? "")\" at \(check1?.url ?? "")")
        let image = try slidePNG("Acme serves 40 banks")
        desk.claims.addFile(image, to: deal)
        let pages = try desk.store.queries.evidence(of: deal, author: "Aditya").filter { $0.consent?.kind == .dropped }
        check(pages.count == 2, "an image is read by Vision as one page too: \(pages.last?.line.suffix(40) ?? "")")

        try desk.allow([.web: false])
        desk.claims.toggle(found[1], in: deal)
        await desk.claims.checkChosen(in: deal)
        check(
            desk.claims.problems.text?.contains("Web research is off") == true,
            "with web research off the check sends nothing: \"\(desk.claims.problems.text ?? "")\"")
    }

    @MainActor static func g2() async throws {
        let desk = try Desk(replies: [queries, contradicted])
        defer { desk.close() }
        try desk.allow([.web: true])
        let deal = try desk.newDeal("Acme")
        desk.claims.addClaim("  ", to: deal)
        check(desk.claims.state(of: deal).claims.isEmpty, "an empty claim adds nothing")
        desk.claims.addClaim("Acme raised $20 million in its seed round.", to: deal)
        let claim = try require(desk.claims.state(of: deal).claims.first)
        check(
            claim.source == .typed && claim.label != nil && claim.quote == claim.text,
            "the typed claim is a fact in the person's own words (source \(claim.source?.rawValue ?? "none"), known label)"
        )
        desk.claims.toggle(claim, in: deal)
        await desk.claims.checkChosen(in: deal)
        let inputs = desk.model.inputs.withLock { $0 }
        check(
            inputs.first == "Company: Acme\nClaim: Acme raised $20 million in its seed round.",
            "the query writer got only: \(inputs.first?.replacingOccurrences(of: "\n", with: " | ") ?? "nothing")")
        check(
            desk.claims.state(of: deal).checks.first?.verdict == .contradicted,
            "and the claim was checked like any other")
    }
}

extension Gates {
    @MainActor static func g3(png: URL) async throws {
        let chat = try whatsAppFolderWithPitch()
        let desk = try Desk(template: .fund.adding(optional: [MachineTemplate.dealsFromChats.id]), whatsApp: chat)
        defer { desk.close() }
        let dealA = try desk.newDeal("Acme")
        desk.claims.addFile(try deckPDF(lines: deck, named: "acme-deck.pdf"), to: dealA)

        desk.model.append([rating])
        await desk.claims.rate(dealA)
        desk.deals.refresh()
        let rated = desk.claims.state(of: dealA)
        let lines = try desk.store.queries.evidence(of: dealA, author: "Aditya")
        let cited = lines.first { $0.id == rated.rating?.citeFirst }
        check(
            rated.triage?.rating == "hot" && desk.deals.digests[dealA.id]?.triage?.rating == "hot",
            "a deal added by hand, with no mail, is rated \(rated.triage?.rating ?? "not rated") by the thesis"
        )
        check(
            cited != nil && cited?.consent?.kind == .dropped,
            "the why card cites line \(rated.rating?.citeFirst ?? 0) of the deal's evidence: \"\(rated.rating?.quote ?? "")\" in \(cited?.line.prefix(40) ?? "")…"
        )
        let decided = rated.triage?.decidedBy.compactMap { id in
            rated.triage?.results.first { $0.id == id }?.rule.summary
        }
        check(decided?.isEmpty == false, "it says which rules decided: \(decided ?? [])")

        desk.model.append([madeUpRating])
        await desk.claims.rate(dealA)
        let guarded = desk.claims.state(of: dealA).triage
        check(
            guarded?.results.first?.verdict == .unknown && guarded?.rating == "warm" && guarded?.needsReview == true,
            "a quote the model made up is refused: the must rule reads unknown, the deal is held at \(guarded?.rating ?? "?"), not hot, and asks for review: \(guarded?.review ?? [])"
        )

        desk.model.append([rating])
        await desk.claims.rate(dealA)
        let latest = try require(desk.claims.state(of: dealA).rating)
        desk.claims.mark(latest, as: .rejected, in: dealA)
        desk.deals.refresh()
        check(
            desk.claims.state(of: dealA).rating?.state == .rejected && desk.deals.digests[dealA.id]?.triage == nil,
            "a mark of wrong overrides the rating: the deal shows none")

        let source = try require(
            desk.crew.machines.first { $0.machine.template == "vc.deals-chats" }?.source as? WhatsAppSource)
        try source.loadGroups()
        try source.choose(try require(source.groups.first))
        desk.model.append([chatDeal])
        let today = WorkDay(containing: .now)
        let machine = try require(desk.crew.machines.first { $0.machine.template == "vc.deals-chats" })
        await machine.reading.read(today)
        let item = try require(machine.items(on: today).first)
        let idB = try require(desk.deals.create(title: item["company"]))
        let link = WorkEvent(
            object: idB, author: "Aditya", clock: try desk.store.queries.nextClock(), at: .now, kind: .link,
            item: LinkedItem(machine: machine.machine, item: item, audience: ["Aditya"]))
        try desk.store.append([link])
        desk.deals.refresh()
        let dealB = try require(desk.deals.deal(idB))
        desk.model.append([chatRating])
        await desk.claims.rate(dealB)
        let ratedB = desk.claims.state(of: dealB)
        let linesB = try desk.store.queries.evidence(of: dealB, author: "Aditya")
        check(
            ratedB.triage?.rating == "hot" && linesB.allSatisfy { $0.consent?.kind == .whatsapp },
            "a deal found in a WhatsApp chat is rated the same way, over \(linesB.count) chat lines: \(ratedB.triage?.rating ?? "none")"
        )
        let before = desk.model.inputs.withLock { $0.count }
        try desk.allow([.whatsapp: false], labels: [.whatsapp: [teamGroup]])
        await desk.claims.rate(dealB)
        check(
            desk.claims.problems.text?.contains("WhatsApp is switched off") == true
                && desk.model.inputs.withLock { $0.count } == before,
            "with WhatsApp off the chat lines are not read and no model call is made: \"\(desk.claims.problems.text ?? "")\""
        )

        try desk.allow([.whatsapp: true, .web: true], labels: [.whatsapp: [teamGroup]])
        desk.model.append([extraction, queries, contradicted])
        await desk.claims.extract(from: dealA)
        desk.claims.addClaim("Acme has 12 paying merchants.", to: dealA)
        desk.claims.toggle(try require(desk.claims.state(of: dealA).claims.first), in: dealA)
        await desk.claims.checkChosen(in: dealA)
        desk.deals.refresh()
        desk.model.append([rating])
        await desk.claims.rate(dealA)
        desk.deals.refresh()
        try await Renders.dealPage(try require(desk.deals.deal(dealA.id)), desk: desk, png: png)
    }

    static func whatsAppFolderWithPitch() throws -> URL {
        try whatsAppFolder([
            ChatMessage(text: "Beta Pay is raising a seed round. 12 merchants pay us already.", at: noon(daysAgo: 0))
        ])
    }

    @MainActor static func g4() async throws {
        let chats = MachineTemplate.dealsFromChats.spec
        let mail = MachineTemplate.dealIntake.spec
        check(
            chats.source == .whatsappChat && mail.source == .mail
                && chats.fields == mail.fields && chats.criteria == mail.criteria && chats.claimTypes == mail.claimTypes
                && chats.view == mail.view,
            "\"Deals from chats\" is the deal-intake spec with another source: same fields, criteria, claim types and view"
        )
        let plain = TeamTemplate.fund.setupQuestions.first { $0.kind == .criteria }
        let chosen = TeamTemplate.fund.adding(optional: [MachineTemplate.dealsFromChats.id])
        let merged = chosen.setupQuestions.filter { $0.kind == .criteria }
        check(
            plain?.machineNames == ["Deal intake", "Outbound"] && merged.count == 1
                && merged[0].machineNames == ["Deal intake", "Outbound", "Deals from chats"],
            "one criteria question serves \(merged.first?.machineNames ?? []); without the optional machine it serves \(plain?.machineNames ?? [])"
        )
        check(
            TeamTemplate.fund.sources == [.mail, .web, .screenText] && chosen.sources.contains(.whatsapp),
            "a Fund starts without WhatsApp; asking for \"Deals from chats\" adds it: \(chosen.sources.map(\.rawValue))"
        )
        let desk = try Desk(template: nil)
        defer { desk.close() }
        let onboarding = desk.onboarding(choosing: .fund)
        onboarding.include(try require(TeamTemplate.fund.optionalMachines.first), true)
        check(
            onboarding.template.seeds.map(\.name) == [
                "Deal intake", "Outbound", "Founder check", "Signals", "Deals from chats",
            ],
            "onboarding makes the machine only when asked: \(onboarding.template.seeds.map(\.name))")
    }
}

extension Gates {
    static func dealReply(
        _ company: String, stage: String, stageAnswer: String, tractionAnswer: String, quote: String
    ) -> String {
        """
        {"items":[{"company":"\(company)","sector":"software","stage":"\(stage)","from":"a founder","r_stage":"\(stageAnswer)","r_stage_quote":"\(quote)","r_stage_reason":"The round is named.","r_traction":"\(tractionAnswer)","r_traction_quote":"\(quote)","r_traction_reason":"The mail says so.","cite":@\(company)@,"object":"","quote":"\(quote)"}]}
        """
    }

    static let noTime = """
        {"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}
        """

    static func pipReply(person: String, text: String, quote: String) -> String {
        """
        {"items":[{"person":"\(person)","project":"Launch","kind":"commitment","text":"\(text)","when":\(noTime),"stance":"said","asks":"team","relation":{"kind":"new","handle":"","outcome":""},"cite":@\(quote)@,"object":"","quote":"\(quote)"}]}
        """
    }

    @MainActor static func g7(png: URL) async throws {
        try await fundFirstLook(png: png)
        try await startupFirstLook(png: png)
        try await skip()
    }

    @MainActor static func advance(_ onboarding: OnboardingModel, to screen: OnboardingScreen) {
        for _ in 0..<OnboardingScreen.allCases.count where onboarding.screen != screen {
            if onboarding.screen == .team { onboarding.teamModel.team.name = "Brave Capital" }
            onboarding.next()
        }
    }

    @MainActor static func fundFirstLook(png: URL) async throws {
        let desk = try Desk(template: nil)
        defer { desk.close() }
        try desk.allow([.mail: true], labels: [.mail: ["Deals"]])
        try keepMail(
            "Cobalt Works is raising a Series C. We have 900 employees.", from: "raj@cobalt.example", thread: "T1",
            daysAgo: 9, in: desk)
        try keepMail(
            "Beta Pay is raising a pre-seed round. 12 merchants pay us.", from: "asha@beta.example", thread: "T2",
            daysAgo: 5, in: desk)
        try keepMail(
            "Acme Payroll is raising a seed round. We serve 40 banks.", from: "priya@acme.example", thread: "T3",
            daysAgo: 2, in: desk)
        let onboarding = desk.onboarding(choosing: .fund)
        advance(onboarding, to: .firstLook)
        let look = FirstLookModel(crew: desk.crew, template: onboarding.template, today: WorkDay(containing: .now))
        await look.estimate()
        check(
            onboarding.screen == .firstLook && look.machines.first?.spec.source == .mail,
            "Fund: the first look reads \(look.machines.map(\.name)), chosen from the template's machines")
        check(
            look.cost.calls == 3 && desk.model.inputs.withLock { $0.isEmpty },
            "the cost shows before anything is read: at most \(look.cost.calls) model calls, about "
                + "\(look.cost.totalUSD.formatted(.currency(code: "USD"))); model calls so far: 0")
        look.days = 4
        await look.estimate()
        check(look.cost.calls == 1, "shortened to \(look.days) days the cost falls to \(look.cost.calls) call")
        try await Renders.firstLookPlan(
            onboarding: onboarding, crew: desk.crew, png: png, named: "onboarding-fund-first-look-cost")
        look.days = 30
        await look.estimate()
        desk.model.append([
            dealReply("Cobalt Works", stage: "later", stageAnswer: "no", tractionAnswer: "no", quote: "Series C"),
            dealReply(
                "Beta Pay", stage: "pre-seed", stageAnswer: "yes", tractionAnswer: "yes", quote: "12 merchants pay us"),
            dealReply(
                "Acme Payroll", stage: "seed", stageAnswer: "yes", tractionAnswer: "yes", quote: "We serve 40 banks"),
        ])
        await look.run()
        check(
            look.rows.count == 3 && look.rows.map(\.triage?.rating) == ["hot", "hot", "cold"],
            "the deals of the period, rated against the thesis, best first: \(look.rows.map { ($0.fact.item["company"], $0.triage?.rating ?? "") })"
        )
        check(
            look.rows.allSatisfy { !$0.fact.item.quote.isEmpty && $0.triage?.results.isEmpty == false },
            "each row shows the person's quote first and its why card")
        let first = try require(look.rows.first)
        look.mark(first, as: .confirmed)
        check(
            look.rows.first { $0.id == first.id }?.fact.item.state == .confirmed,
            "a one-step mark on a row is kept: \(look.rows.first { $0.id == first.id }?.fact.item.state.rawValue ?? "")"
        )
        onboarding.hasLookedFirst = true
        try await Renders.firstLookResult(
            look: look, onboarding: onboarding, png: png, named: "onboarding-fund-first-look")
    }

    @MainActor static func startupFirstLook(png: URL) async throws {
        let chat = try whatsAppFolder([
            ChatMessage(text: "I will send the cap table by Friday", at: noon(daysAgo: 3)),
            ChatMessage(text: "Asha will fix the login bug tomorrow", fromMe: true, at: noon(daysAgo: 1)),
        ])
        let desk = try Desk(template: nil, whatsApp: chat)
        defer { desk.close() }
        let onboarding = desk.onboarding(choosing: .startupTeam)
        advance(onboarding, to: .firstLook)
        let pip = try require(desk.crew.factKeepers.first)
        let source = try require(pip.source as? WhatsAppSource)
        try source.loadGroups()
        try source.choose(try require(source.groups.first))
        let look = FirstLookModel(crew: desk.crew, template: onboarding.template, today: WorkDay(containing: .now))
        await look.estimate()
        check(
            look.machines.map(\.name) == ["Pip"] && look.cost.calls == 2 && desk.model.inputs.withLock { $0.isEmpty },
            "Startup team: the first look reads \(look.machines.map(\.name)); cost shown first: at most \(look.cost.calls) calls"
        )
        desk.model.append([
            pipReply(person: "Asha", text: "Send the cap table by Friday.", quote: "send the cap table by Friday"),
            pipReply(person: "Asha", text: "Fix the login bug.", quote: "fix the login bug tomorrow"),
        ])
        await look.run()
        check(
            look.rows.count == 2 && look.rows.allSatisfy { $0.triage == nil && $0.fact.item["kind"] == "commitment" },
            "the template's main view is the open commitments: \(look.rows.map(\.fact.item.quote))")
        onboarding.hasLookedFirst = true
        try await Renders.firstLookResult(
            look: look, onboarding: onboarding, png: png, named: "onboarding-startup-first-look")
    }

    @MainActor static func skip() async throws {
        let desk = try Desk(template: nil)
        defer { desk.close() }
        let onboarding = desk.onboarding(choosing: .startupTeam)
        advance(onboarding, to: .firstLook)
        check(
            onboarding.screen == .firstLook && !onboarding.hasLookedFirst, "the step offers Skip while nothing was read"
        )
        onboarding.next()
        check(
            onboarding.screen == .done && desk.model.inputs.withLock { $0.isEmpty },
            "Skip goes on to the last step and no model call was made")
        onboarding.next()
        check(onboarding.isFinished, "and setup finishes")
    }

    @MainActor static func g8(png: URL) async throws {
        let desk = try Desk(template: .fund)
        defer { desk.close() }
        let won = try require(ObjectTypes.deal.firstStage(meaning: .won))
        let acme = try desk.newDeal("Acme")
        desk.deals.move(acme, to: won.id)
        let beta = try desk.newDeal("Beta Pay")
        desk.deals.pass(beta, reason: "too early", revisit: nil)
        _ = try desk.newDeal("Cobalt Works")
        let list = WatchlistModel(store: desk.store)
        check(
            list.fromDeals.map(\.name).sorted() == ["Acme", "Beta Pay"],
            "the deals in a won or a watch stage are offered, the open deal is not: \(list.fromDeals.map { "\($0.name) (\($0.status.rawValue))" }.sorted())"
        )
        list.follow("Gamma Labs", domain: "https://www.gamma.example/about", status: .passed)
        list.followDeals()
        let followed = list.followed.map { "\($0.name) \($0.status.rawValue) \($0.domain ?? "-")" }.sorted()
        check(
            followed == ["Acme portfolio -", "Beta Pay passed -", "Gamma Labs passed gamma.example"]
                && list.fromDeals.isEmpty,
            "the typed company and the imported deals are followed: \(followed)")
        list.follow("Gamma Labs", domain: "", status: .portfolio)
        check(list.followed.count == 3, "a company named twice is followed once")

        var renamed = ObjectTypes.deal
        renamed.stages = renamed.stages.map { stage in
            var stage = stage
            stage.label = "Column \(Int(stage.order))"
            return stage
        }
        let folded = WorkObject.fold(try desk.store.queries.workEvents(), viewer: "", type: { _ in renamed })
            .filter { $0.kind == "deal" }
        check(
            folded.flatMap(\.stageLabels).allSatisfy { $0.hasPrefix("Column") }
                && WatchedCompany.inStages(of: folded).map(\.name).sorted() == ["Acme", "Beta Pay"],
            "with every stage label renamed (\(Set(folded.flatMap(\.stageLabels)).sorted())) the same deals import")
        let empty = try Desk(template: .fund)
        defer { empty.close() }
        try await Renders.watchlist(crew: desk.crew, png: png)
        _ = empty
    }
}
