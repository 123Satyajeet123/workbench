import Foundation
import Testing

@testable import WorkbenchCore

/// Entity matching is code: normalised names, aliases and domains. No fuzzy match.
@Suite struct NewsMatchingTests {
    @Test func aLegalFormIsDroppedSoTheLegalNameAndTheBrandMeet() {
        #expect(CompanyName.normal("Bolt Pay Private Limited") == "bolt pay")
        #expect(CompanyName.normal("Bolt Pay Pvt. Ltd.") == "bolt pay")
        #expect(CompanyName.normal("BOLT PAY LLP") == "bolt pay")
        #expect(CompanyName.normal("Zoho Corporation Pvt Ltd") == "zoho")
        #expect(CompanyName.normal("Café & Co") == "cafe and")
        #expect(CompanyName.normal("Limited") == "limited", "a name that is only a form stays")
        #expect(CompanyName.terms(name: "Bolt Technologies Pvt Ltd", aliases: []) == ["bolt technologies", "bolt"])
        #expect(CompanyName.terms(name: "Ola", aliases: ["Ola Cabs"]) == ["ola", "ola cabs"])
        #expect(CompanyName.terms(name: "Zo", aliases: []).isEmpty, "two letters never match by name")
    }

    @Test func domainsAreTypedInAnyShape() {
        #expect(CompanyName.domain("https://www.Bolt.example/about?x=1") == "bolt.example")
        #expect(CompanyName.domain("bolt.example") == "bolt.example")
        #expect(CompanyName.domain("bolt") == nil)
    }

    @Test func aLegalNameInTheListMatchesTheBrandInTheNews() {
        let bolt = company("Bolt Pay Private Limited")
        let news = article("Bolt Pay lays off 40", text: "The fintech Bolt Pay cut staff.")
        #expect(EntityMatcher.candidates(in: news, among: [bolt]).map(\.company.id) == [bolt.id])
    }

    @Test func aNameMatchesAsWholeWordsOnly() {
        let bolt = company("Bolt")
        #expect(
            EntityMatcher.candidates(in: article("Lightning bolts", text: "Boltzmann spoke."), among: [bolt]).isEmpty)
        #expect(EntityMatcher.candidates(in: article("Bolt, the app", text: "x"), among: [bolt]).count == 1)
    }

    @Test func anAliasTheInvestorConfirmedMatches() {
        let bolt = company("Bolt Pay", aliases: ["BoltX"])
        let news = article("BoltX raises seed", text: "x")
        #expect(EntityMatcher.candidates(in: news, among: [bolt]).count == 1)
        #expect(EntityMatcher.candidates(in: news, among: [company("Bolt Pay")]).isEmpty, "no alias, no match")
    }

    @Test func aDomainInTheTextMatchesACompanyWhoseNameIsNotThere() {
        let acme = company("Acme", domain: "acme.example")
        let news = article("A new payroll tool", text: "Details at https://www.acme.example/launch today.")
        #expect(EntityMatcher.candidates(in: news, among: [acme]).count == 1)
        #expect(EntityMatcher.candidates(in: article("Tool", text: "see notacme.example"), among: [acme]).isEmpty)
    }

    @Test func twoCompaniesWithOneNameAreBothCandidatesWithUniqueLabels() {
        let first = company("Bolt Pay", status: .portfolio)
        let second = company("Bolt Pay Pvt Ltd", status: .passed)
        let found = EntityMatcher.candidates(in: article("Bolt Pay raises", text: "x"), among: [first, second])
        #expect(found.map(\.label) == ["Bolt Pay (portfolio)", "Bolt Pay Pvt Ltd (passed)"])
    }

    @Test func aDomainInTheTextSettlesWhichOfTwoSameNamedCompaniesIsMeant() {
        let first = company("Bolt Pay", domain: "boltpay.example")
        let second = company("Bolt Pay", domain: "bolt.example")
        let news = article("Bolt Pay raises", text: "Read more on boltpay.example.")
        #expect(EntityMatcher.candidates(in: news, among: [first, second]).map(\.company.id) == [first.id])
    }

    @Test func theListHoldsInvestedAndPassedDealsAndHandAddedCompaniesOnceByDomain() throws {
        let invested = try deal("Acme Pvt Ltd", stage: "Invested", id: "d1")
        let passed = try deal("Bolt Pay", stage: "Rejected", id: "d2")
        let early = try deal("Zeta", stage: "Screen", id: "d3")
        let entries = [
            WatchEntry(aliases: ["Acme Payroll"], domain: "acme.example", deal: "d1"),
            WatchEntry(name: "Hand Made", domain: "acme.example"), WatchEntry(name: "Orbit"),
        ]
        let list = WatchedCompany.list(deals: [invested, passed, early], entries: entries)
        #expect(list.map(\.name) == ["Acme Pvt Ltd", "Bolt Pay", "Orbit"], "Screen is not followed; one acme.example")
        #expect(list.map(\.status) == [.portfolio, .passed, .portfolio])
        #expect(list[0].aliases == ["Acme Payroll"] && list[0].domain == "acme.example")
    }
}
