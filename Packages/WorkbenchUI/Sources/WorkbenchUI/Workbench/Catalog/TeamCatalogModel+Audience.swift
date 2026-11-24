import Foundation
import LocalSources
import WorkbenchCore

extension TeamCatalogModel {
    /// People other than its author who approved the version shared now.
    func approvers(of machine: SharedMachine, in place: Place) -> [String] {
        machine.approvers(in: reviews[place] ?? [])
    }

    /// This person's review of the shared version, if any.
    func myReview(of machine: SharedMachine, in place: Place) -> MachineReview? {
        (reviews[place] ?? []).first {
            $0.reviewer == me && $0.author == machine.author && $0.task == machine.spec.task
                && $0.version == machine.version
        }
    }

    /// Who can already read the machine's source, by the audience rule: a group's linked members; for the founder's
    /// screen and pages, nobody else.
    func readers(of helper: HelperModel) async throws -> (
        recipients: [Team.Person], missing: [Team.Person], group: [WhatsAppMember]
    ) {
        let recipients = (try store.queries.team()?.people ?? []).filter { !$0.isMe }
        guard let group = try await helper.source.shareAudience() else { return (recipients, recipients, []) }
        let readers = Audience.readers(links: try store.queries.whatsappLinks(), group: Set(group.map(\.jid)))
        return (recipients, Audience.missing(recipients: recipients, readers: readers), group)
    }
}
