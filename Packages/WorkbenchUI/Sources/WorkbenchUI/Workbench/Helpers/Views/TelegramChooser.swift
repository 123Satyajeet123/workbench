import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import TelegramReader
import WorkbenchCore

struct TelegramChooser: View {
    let model: HelperModel
    let source: TelegramSource

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SourceHealthMark(source: .telegram)
            if let problem = source.account.revokeProblem {
                Text(problem).textStyle(.callout).foregroundStyle(.supporting)
            }
            Text(
                "\(model.name) reads one Telegram group, only after every person in it agrees, and only the day you ask it to."
            )
            .foregroundStyle(.supporting)
            if let group = source.asking {
                TelegramConsentCard(model: model, source: source, group: group)
            } else {
                step
            }
            if source.isChanging, let current = model.chosenSource {
                Button("Keep \(current)", action: source.keep)
            }
        }
        .task { model.attempt("connect to Telegram") { try source.account.resume() } }
    }

    @ViewBuilder private var step: some View {
        switch source.account.login {
        case .signedOut where !source.account.hasKeys: TelegramKeysCard(model: model, account: source.account)
        case .failed(let why): TelegramFailedCard(model: model, account: source.account, why: why)
        case .signedOut: TelegramSignedOutCard(model: model, account: source.account)
        case .paused: TelegramPausedCard(model: model, account: source.account)
        case .connecting: ProgressView("Connecting to Telegram…").controlSize(.small)
        case .scan(let link): TelegramScanCard(link: link)
        case .password(let hint): TelegramPasswordCard(model: model, account: source.account, hint: hint)
        case .ready(let name): TelegramGroupsCard(model: model, source: source, name: name)
        }
    }
}

private struct TelegramKeysCard: View {
    let model: HelperModel
    let account: TelegramAccount
    @State private var apiID = ""
    @State private var apiHash = ""

    var body: some View {
        Card(title: "Connect Telegram", symbol: "paperplane") {
            Text(
                "Telegram lets an app sign in only with an API ID of its own. Open my.telegram.org, sign in with your phone number, choose API development tools and create an app with any name. Paste its two values here. They stay in this Mac's keychain."
            )
            .foregroundStyle(.supporting)
            if let page = URL(string: TelegramAccount.keysPage) {
                Link("Open my.telegram.org", destination: page).foregroundStyle(.linkText)
            }
            TextField("API ID", text: $apiID).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            SecureField("API hash", text: $apiHash).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            Button("Connect") {
                model.attempt("connect to Telegram") { try account.connect(apiID: apiID, apiHash: apiHash) }
            }
            .buttonStyle(.primary).disabled(apiID.isEmpty || apiHash.isEmpty)
        }
    }
}

private struct TelegramFailedCard: View {
    let model: HelperModel
    let account: TelegramAccount
    let why: String

    var body: some View {
        Card(title: "Telegram did not connect", symbol: "exclamationmark.triangle") {
            Text(why).foregroundStyle(.supporting)
            HStack {
                Button("Try again") { model.attempt("connect to Telegram") { try account.resume() } }
                    .buttonStyle(.primary)
                Button("Use other keys") { model.attempt("forget the Telegram keys", account.forgetKeys) }
            }
        }
    }
}

private struct TelegramSignedOutCard: View {
    let model: HelperModel
    let account: TelegramAccount

    var body: some View {
        Card(title: "Signed out of Telegram", symbol: "paperplane") {
            Text("Sign in again with a QR code from your phone.").foregroundStyle(.supporting)
            HStack {
                Button("Sign in") { model.attempt("connect to Telegram") { try account.resume() } }
                    .buttonStyle(.primary)
                Button("Use other keys") { model.attempt("forget the Telegram keys", account.forgetKeys) }
            }
        }
    }
}

private struct TelegramPausedCard: View {
    let model: HelperModel
    let account: TelegramAccount

    var body: some View {
        Card(title: "Telegram is paused", symbol: "pause.circle") {
            Text(
                "Capture or the Telegram switch is off, so Workbench closed its Telegram connection. You stay signed in."
            )
            .foregroundStyle(.supporting)
            Button("Connect again") { model.attempt("connect to Telegram") { try account.resume() } }
                .buttonStyle(.primary)
        }
    }
}

private struct TelegramScanCard: View {
    let link: String

    var body: some View {
        Card(title: "Scan with your phone", symbol: "qrcode") {
            Text("On your phone, open Telegram › Settings › Devices › Link Desktop Device, and scan this code.")
                .foregroundStyle(.supporting)
            if let image = Self.code(for: link) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 200, height: 200)
                    .padding(Space.s).background(.white, in: .rect(cornerRadius: Radius.control))
                    .accessibilityLabel("Telegram sign-in code")
            }
        }
    }

    static func code(for link: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let picture = NSCIImageRep(ciImage: output)
        let image = NSImage(size: picture.size)
        image.addRepresentation(picture)
        return image
    }
}

private struct TelegramPasswordCard: View {
    let model: HelperModel
    let account: TelegramAccount
    let hint: String
    @State private var password = ""

    var body: some View {
        Card(title: "Your Telegram password", symbol: "lock") {
            Text(
                hint.isEmpty
                    ? "Your account has a cloud password. Type it to finish signing in."
                    : "Your account has a cloud password. Hint: \(hint)."
            )
            .foregroundStyle(.supporting)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                .onSubmit(signIn)
            Button("Sign in", action: signIn).buttonStyle(.primary).disabled(password.isEmpty)
        }
    }

    private func signIn() {
        let typed = password
        Task {
            do {
                try await account.checkPassword(typed)
                password = ""
            } catch {
                model.problems.report("sign in to Telegram", error)
            }
        }
    }
}

private struct TelegramGroupsCard: View {
    let model: HelperModel
    let source: TelegramSource
    let name: String
    @State private var query = ""
    @State private var isLoading = false

    var body: some View {
        Card(title: "One group", symbol: "person.3") {
            Text("Signed in to Telegram as \(name). Choose your team's group.").foregroundStyle(.supporting)
            if source.groups.isEmpty {
                Button(isLoading ? "Listing your groups…" : "Show my Telegram groups") {
                    run("list your Telegram groups", source.loadGroups)
                }
                .buttonStyle(.primary).disabled(isLoading)
            } else {
                TextField("Search your groups", text: $query, prompt: Text("Search your groups"))
                    .textFieldStyle(.roundedBorder)
                let found = FuzzySearch.filter(source.groups, by: query, name: \.title)
                if found.isEmpty { Text("No group matches “\(query)”.").foregroundStyle(.supporting) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(found) { group in
                        HStack {
                            Text(group.title).lineLimit(1)
                            Text("\(group.memberCount) people").textStyle(.callout).foregroundStyle(.supporting)
                            Spacer()
                            Button("Choose") { run("list the group's members") { try await source.ask(group) } }
                                .buttonStyle(.ghost).foregroundStyle(.linkText)
                        }
                        .padding(.vertical, Space.xs)
                        if group.id != found.last?.id { Divider() }
                    }
                }
            }
            Button("Sign out of Telegram") { run("sign out of Telegram", source.account.signOut) }
                .buttonStyle(.ghost).foregroundStyle(.supporting)
        }
    }

    private func run(_ step: String, _ work: @escaping () async throws -> Void) {
        isLoading = true
        Task {
            do { try await work() } catch { model.problems.report(step, error) }
            isLoading = false
        }
    }
}

private struct TelegramConsentCard: View {
    let model: HelperModel
    let source: TelegramSource
    let group: TelegramChat
    @Environment(ModelSettings.self) private var models
    @State private var agreed = false

    var body: some View {
        Card(title: "Has everyone in \(group.title) agreed?", symbol: "hand.raised") {
            Text(
                "Telegram lets an app pass a chat to an AI model only when every person in it agrees. \(model.name) sends this group's messages to \(models.choice.title) to keep your team's facts. Ask each person below and tell them that."
            )
            .foregroundStyle(.supporting)
            Text(people).textStyle(.callout)
            if source.askingPeople.count + 1 < group.memberCount {
                Text(
                    "Telegram shows \(source.askingPeople.count + 1) of the \(group.memberCount) people here. Ask every one of them, listed or not."
                )
                .textStyle(.callout).foregroundStyle(.supporting)
            }
            Toggle("Every person in this group has agreed", isOn: $agreed).toggleStyle(.checkbox)
            HStack {
                Button("Read this group") {
                    model.attempt("save the group", source.confirmEveryoneAgreed)
                    model.reload()
                }
                .buttonStyle(.primary).disabled(!agreed)
                Button("Back", action: source.backToGroups)
            }
            Text("If someone new joins, \(model.name) stops reading and asks you again.")
                .textStyle(.callout).foregroundStyle(.supporting)
        }
    }

    private var people: String {
        source.askingPeople.isEmpty
            ? "No one else is in this group." : source.askingPeople.map(\.name).joined(separator: ", ")
    }
}
