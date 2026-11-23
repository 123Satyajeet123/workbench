import Foundation

/// The built-in object types. A team's own types come later; these are data in code. A folder and a page are types
/// with no stages: the tree holds every kind of work object, so there is no second kind of folder.
public enum ObjectTypes {
    public static let builtIn = [deal, project, company, folder, page, machinePage]

    public static func type(for kind: String) -> ObjectType {
        builtIn.first { $0.id == kind } ?? .unlisted(kind)
    }

    /// The fund's deal pipeline as it stood before stages were data (research 27 §1.1, with the three a VC analyst
    /// asked for). Old deal events hold these labels, and fold to these ids.
    public static let deal = ObjectType(
        id: "deal", noun: "deal",
        fields: [
            FieldDef(id: "company", label: "Company", kind: .text),
            FieldDef(id: "owner", label: "Owner", kind: .person),
            FieldDef(id: "reason", label: "Reason", kind: .text),
            FieldDef(id: "revisit", label: "Revisit", kind: .date),
        ],
        stages: [
            StageDef(id: "deal.inbox", label: "Inbox", order: 1, meaning: .open),
            StageDef(id: "deal.screen", label: "Screen", order: 2, meaning: .open),
            StageDef(id: "deal.in-conversation", label: "In conversation", order: 3, meaning: .open),
            StageDef(
                id: "deal.action-required", label: "Action required", order: 4, meaning: .waiting,
                resumes: "deal.in-conversation"),
            StageDef(id: "deal.founder-meeting", label: "Founder meeting", order: 5, meaning: .open),
            StageDef(id: "deal.diligence", label: "Diligence", order: 6, meaning: .open),
            StageDef(id: "deal.decision", label: "Decision", order: 7, meaning: .open),
            StageDef(id: "deal.invested", label: "Invested", order: 8, meaning: .won),
            StageDef(
                id: "deal.rejected", label: "Rejected", order: 9, meaning: .watch, requires: ["reason"],
                after: [TimerRule(field: "revisit", defaultAfterDays: 180)]),
        ])
}

extension ObjectTypes {
    public static let company = ObjectType(
        id: "company", noun: "company", fields: [FieldDef(id: "domain", label: "Website", kind: .text)], stages: [])
    public static let folder = ObjectType(id: "folder", noun: "folder", stages: [])
    public static let page = ObjectType(id: "page", noun: "page", stages: [])
    /// The page of one machine. Its parent is the folder the machine serves.
    public static let machinePage = ObjectType(id: "machine-page", noun: "machine", stages: [])

    /// The kinds a fact may be filed under: every kind except the pages that hold setup or words.
    public static let homes = builtIn.filter { $0.id != page.id && $0.id != machinePage.id }
}

extension WorkObject {
    /// The deal stage a wait stands in, for the code that settles a wait (removed when timers replace it).
    public static let actionRequired = ObjectTypes.deal.firstStage(meaning: .waiting)!.id
}
