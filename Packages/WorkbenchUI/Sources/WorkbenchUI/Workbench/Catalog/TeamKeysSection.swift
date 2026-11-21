import SwiftUI
import WorkbenchCore

/// This Mac's team keys and the people the team trusts. Teammates compare fingerprints once, by call or in person;
/// the founder's confirmation is what makes a person count.
struct TeamKeysSection: View {
    @Environment(TeamCatalogModel.self) private var catalog

    private var trust: TeamTrustModel { catalog.trust }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Team keys").textStyle(.title3)
            if let problem = trust.problem { ProblemBanner(text: problem, dismiss: trust.dismissProblem) }
            Text("Your fingerprint").textStyle(.caption).foregroundStyle(.supporting)
            Text(trust.fingerprint).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text(
                "Signing key \(trust.card.signing.prefix(6).hexadecimal)… · agreement key \(trust.card.agreement.prefix(6).hexadecimal)…"
            )
            .textStyle(.caption).foregroundStyle(.supporting).textSelection(.enabled)
            foundingLine
            ForEach(trust.waiting) { WaitingRow(hello: $0) }
            ForEach(trust.members, id: \.card) { MemberRow(member: $0) }
            Text(
                "Nothing in the team folder can be read without a key. A person you remove keeps what they already read, and cannot read what is sent after."
            )
            .textStyle(.caption).foregroundStyle(.supporting)
            if trust.unverified > 0 {
                Text("\(trust.unverified) events could not be verified and were left out.").textStyle(.caption)
                    .foregroundStyle(Tone.bad.color)
            }
            ForEach(trust.gaps.keys.sorted(), id: \.self) { name in
                Text("\(name): \(trust.gaps[name]?.count ?? 0) envelopes missing: dropped, or not arrived yet.")
                    .textStyle(.caption).foregroundStyle(Tone.bad.color)
            }
        }
    }

    @ViewBuilder private var foundingLine: some View {
        if let founder = trust.founder {
            Text(
                trust.isFounder
                    ? "You are the founder: people count once you confirm their fingerprint."
                    : "\(founder.name) is the founder you trust (\(founder.card.spoken))."
            )
            .textStyle(.callout)
        } else {
            HStack {
                Text("Choose who decides who is in the team.").textStyle(.callout).foregroundStyle(.supporting)
                Button("I am the founder") { catalog.trust.becomeFounder(named: catalog.me) }
                    .help("Use this on the founder's Mac. Everyone else confirms the founder's fingerprint below.")
            }
        }
    }
}

private struct WaitingRow: View {
    let hello: MembershipEvent
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(hello.subject).textStyle(.headline)
                Text(hello.card.spoken).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            Spacer()
            Button(catalog.trust.founder == nil ? "This is my founder" : "Fingerprint matches: add") {
                catalog.trust.confirm(hello, with: catalog.sync)
                catalog.refresh()
            }
            .help("Compare the fingerprint with \(hello.subject) by call or in person first.")
        }
    }
}

private struct MemberRow: View {
    let member: Roster.Member
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        HStack {
            Monogram(name: member.name, size: 22)
            Text(member.name)
            Text(member.card.spoken).font(.system(.caption, design: .monospaced)).foregroundStyle(.supporting)
            Spacer()
            if catalog.trust.isFounder && member.card != catalog.trust.card {
                Button("Remove") {
                    catalog.trust.remove(member, with: catalog.sync)
                    catalog.refresh()
                }
            }
        }
    }
}

extension Data {
    fileprivate var hexadecimal: String { map { String(format: "%02x", $0) }.joined() }
}
