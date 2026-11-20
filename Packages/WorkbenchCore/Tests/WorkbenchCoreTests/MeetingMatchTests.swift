import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct MeetingMatchTests {
    private let me = Meeting.Attendee(name: "Aditya", email: "aditya@fund.vc", isMe: true)
    private let acme = DealIdentity(id: "d1", names: ["Acme Robotics", "Acme"], domains: ["acme-robots.io"])
    private let beta = DealIdentity(id: "d2", names: ["Beta"], domains: ["beta.ai"])

    private func meeting(_ title: String = "Intro", guests: [(String, String)]) -> Meeting {
        Meeting(
            id: "e", calendar: "c", title: title, start: t0, end: t0,
            attendees: [me] + guests.map { Meeting.Attendee(name: $0.0, email: $0.1) })
    }

    private func subjects(_ meeting: Meeting, deals: [DealIdentity] = []) -> [MeetingSubject] {
        MeetingMatch.subjects(of: meeting, people: ["Asha Rao", "Raj"], deals: deals)
    }

    @Test func aGuestMatchesAPersonByExactNameIgnoringCaseAndSpacing() {
        #expect(subjects(meeting(guests: [("asha  RAO", "a@x.org")])) == [.person("Asha Rao")])
    }

    @Test func aSimilarNameIsNotAMatch() {
        #expect(subjects(meeting(guests: [("Asha", "a@x.org"), ("Raj K", "r@x.org")])).isEmpty)
    }

    @Test func theOwnerIsNeverMatchedAsAPerson() {
        let owner = Meeting.Attendee(name: "Raj", email: "raj@fund.vc", isMe: true)
        let own = Meeting(id: "e", calendar: "c", title: "t", start: t0, end: t0, attendees: [owner])
        #expect(subjects(own).isEmpty)
    }

    @Test func aGuestEmailDomainMatchesTheDealThatListsIt() {
        #expect(subjects(meeting(guests: [("X", "x@acme-robots.io")]), deals: [acme, beta]) == [.deal("d1")])
    }

    @Test func aDomainWhoseCompanyLabelIsTheDealNameMatches() {
        #expect(subjects(meeting(guests: [("X", "x@beta.com")]), deals: [acme, beta]) == [.deal("d2")])
    }

    @Test func aThreePartDomainDoesNotMatchByCompanyLabel() {
        #expect(subjects(meeting(guests: [("X", "x@beta.co.uk")]), deals: [beta]).isEmpty)
    }

    @Test func freeMailAndTheOwnersDomainNeverMatchADeal() {
        let gmail = DealIdentity(id: "d3", names: ["Gmail"], domains: ["gmail.com"])
        let fund = DealIdentity(id: "d4", names: ["Fund"], domains: ["fund.vc"])
        let guests = [("X", "x@gmail.com"), ("Y", "y@fund.vc")]
        #expect(subjects(meeting(guests: guests), deals: [gmail, fund]).isEmpty)
    }

    @Test func aDomainTwoDealsClaimIsLeftUnmatched() {
        let twin = DealIdentity(id: "d5", names: ["Acme Two"], domains: ["acme-robots.io"])
        #expect(subjects(meeting(guests: [("X", "x@acme-robots.io")]), deals: [acme, twin]).isEmpty)
    }

    @Test func aTitleThatIsExactlyADealNameMatchesAndASimilarOneDoesNot() {
        #expect(subjects(meeting("acme robotics", guests: []), deals: [acme]) == [.deal("d1")])
        #expect(subjects(meeting("Acme Robotics sync", guests: []), deals: [acme]).isEmpty)
    }

    @Test func aPersonAndADealAreFoundOnceEach() {
        let found = subjects(
            meeting(guests: [("Raj", "raj@acme-robots.io"), ("Asha Rao", "asha@acme-robots.io")]), deals: [acme])
        #expect(found == [.person("Raj"), .person("Asha Rao"), .deal("d1")])
    }

    @Test func domainsAreReadFromEmailsAndBareDomains() {
        let text = "Priya <priya@Acme.com>, see beta.ai. Not e.g. or Inc."
        #expect(MeetingMatch.domains(in: text) == ["acme.com", "beta.ai"])
    }

    @Test func aDealIdentityTakesItsNamesAndDomainsFromItsLinkedItems() throws {
        let item = Item(
            task: "vc.deals-1", day: WorkDay(containing: t0), scope: "", source: .mail, citeFirst: 1, citeLast: 1,
            start: t0, end: t0, fields: ["company": "Acme Robotics", "from": "Priya <p@acme-robots.io>"],
            quote: "Acme is raising", run: 1)
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: .dealIntake, state: .active)
        let linked = LinkedItem(machine: machine, item: item, audience: ["Aditya"])
        let events = [
            WorkEvent(object: "d1", author: "Aditya", clock: 1, at: t0, kind: .create, text: "deal"),
            WorkEvent(object: "d1", author: "Aditya", clock: 2, at: t0, kind: .title, text: "Acme"),
            WorkEvent(object: "d1", author: "Aditya", clock: 3, at: t0, kind: .link, item: linked),
        ]
        let identity = DealIdentity(try #require(WorkObject.fold(events, viewer: "Aditya").first))
        #expect(identity.names == ["Acme", "Acme Robotics"])
        #expect(identity.domains == ["acme-robots.io"])
    }
}
