import Foundation
import Kernel
import LocalSources
import WorkbenchCore

@testable import WorkbenchUI

public struct BuildOptions {
    /// The folder of the synthetic mails: `eml/` with the `.eml` files.
    public var sources: URL
    public var dryRun: Bool
    /// The builder stops reading days when the runs cost this much, in US dollars.
    public var budgetUSD: Double

    public init(sources: URL, dryRun: Bool = false, budgetUSD: Double = 1.8) {
        self.sources = sources
        self.dryRun = dryRun
        self.budgetUSD = budgetUSD
    }
}

public struct BuildReport: Equatable {
    public var mails = 0
    public var decks = 0
    public var whatsAppLines = 0
    public var machines: [String] = []
    public var daysRead = 0
    public var daysLeftUnread = 0
    public var facts = 0
    public var deals = 0
    public var runs = 0
    public var costUSD = 0.0
    public var problems: [String] = []
}

public enum BuildFailure: Error, LocalizedError {
    case noMail(String)
    case heldOut(String)
    case cannotOpen(String)
    case missing(String)
    case modelTermsNotConfirmed
    case modelTermsUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .noMail(let path): "No .eml files in \(path)."
        case .heldOut(let id): "\(id) is dated in 23 Nov to 6 Dec 2026, a held-out study. Nothing there may be used."
        case .cannotOpen(let cause): "The demo store did not open: \(cause)"
        case .missing(let what): "The demo has no \(what)."
        case .modelTermsNotConfirmed:
            """
            Your Workbench has no yes to the model terms, and the builder never gives it for you. Open Workbench on \
            your own profile, confirm the terms in Settings › General › Model, then run the builder again. It copies \
            that yes into the demo. A --dry-run build needs no yes.
            """
        case .modelTermsUnreadable(let cause): "Your yes to the model terms could not be read: \(cause)"
        }
    }
}

/// Builds a demo folder from nothing, using only synthetic sources and the app's own pipelines: the Fund team from its
/// template, the mails through the native host's entry point, the chat through the WhatsApp reader, the days through
/// the machines with the person's own model CLI, and the hot candidates accepted as deals.
@MainActor
public enum DemoBuild {
    public static func run(
        into folder: URL, options: BuildOptions, progress: (String) -> Void = { _ in }
    ) async throws -> BuildReport {
        let letters = try Self.letters(in: options.sources)
        if let late = letters.first(where: { HeldOutWindow.study.contains($0.sent) }) {
            throw BuildFailure.heldOut(late.message)
        }
        let terms = options.dryRun ? nil : try FounderModelTerms.read(from: Profile.yours.defaultFolder)
        try DemoFolder.prepare(folder, yours: Profile.yours.defaultFolder, marker: Profile.builtMarker)
        do {
            return try await build(in: folder, letters: letters, terms: terms, options: options, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func build(
        in folder: URL, letters: [Letter], terms: String?, options: BuildOptions,
        progress: (String) -> Void
    ) async throws -> BuildReport {
        try SyntheticWhatsApp.write(to: Profile.demo.whatsAppContainer(in: folder))
        let session: AppSession
        let clock = MovableClock()
        switch AppLaunch.open(profile: .demo, storeFolder: folder, secrets: Profile.demo.secrets, clock: { clock.now }) {
        case .ready(let opened): session = opened
        case .failed(let failure): throw BuildFailure.cannotOpen(failure.cause)
        }
        defer { session.reminders.stop() }
        if let terms { try session.store.saveState(terms, forKey: ModelTerms.stateKey) }

        try startFundTeam(in: session)
        let intake = try machine(reading: .mail, in: session)
        let pip = try machine(reading: .whatsappChat, in: session)
        let chat = try chooseChat(of: pip)
        try mail(of: intake).choose(MailFeed.label)
        session.capture.setBrowser(MailFeed.browser, named: MailFeed.browserName, on: true)
        let kept = try MailFeed(owner: Profile.demo.owner(secrets: Profile.demo.secrets)).keep(
            letters, in: session.store, at: clock)
        clock.release()
        progress("mails kept \(kept.letters) of \(letters.count), decks kept \(kept.decks)")

        var report = BuildReport(mails: kept.letters, decks: kept.decks)
        let chatDays = days(of: SyntheticWhatsApp.script.map(SyntheticWhatsApp.date(of:)))
        for day in chatDays { _ = try await pip.source.evidence(on: day) }
        report.whatsAppLines = try session.store.queries.currentLines(
            in: [chat.container], from: .distantPast, to: .distantFuture
        ).count

        if !options.dryRun {
            let mailDays = days(of: letters.map(\.sent))
            let work = newestFirstAlternating(
                mailDays.map { (intake, $0) }, chatDays.map { (pip, $0) })
            for (helper, day) in work {
                if try cost(of: session) >= options.budgetUSD {
                    report.daysLeftUnread += 1
                    continue
                }
                helper.show(day)
                let lines = try await helper.source.evidence(on: day).lines.count
                await helper.read()
                report.daysRead += 1
                if let problem = helper.problem { report.problems.append("\(helper.name) \(day): \(problem)") }
                progress(
                    "\(helper.name) \(day.description): \(lines) lines, \(helper.phase), cost \(try cost(of: session))")
            }
            report.deals = try await acceptHotCandidates(of: intake, on: mailDays, in: session)
        }
        report.machines = session.crew.machines.map(\.name)
        report.facts = try session.store.queries.count(of: .item)
        report.runs = try session.store.queries.count(of: .run)
        report.costUSD = try cost(of: session)
        try Profile.markDemoBuilt(in: folder)
        return report
    }

    static func letters(in sources: URL) throws -> [Letter] {
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".eml") }
        guard !files.isEmpty else { throw BuildFailure.noMail(sources.path) }
        return try files.sorted().map { try LetterParser.parse(Data(contentsOf: sources.appending(path: $0))) }
            .sorted { $0.sent < $1.sent }
    }

    /// The newest day of each source first, taking one from each in turn, so a budget that ends early leaves the oldest
    /// days of every source unread and no source empty.
    private static func newestFirstAlternating<T>(_ first: [T], _ second: [T]) -> [T] {
        let (a, b) = (Array(first.reversed()), Array(second.reversed()))
        return (0..<max(a.count, b.count)).flatMap { index in [a[safe: index], b[safe: index]].compactMap { $0 } }
    }

    /// The work days of the dates in the fund's own calendar, so each line falls on the day the fixture means.
    private static func days(of dates: [Date]) -> [WorkDay] {
        Array(Set(dates.map { WorkDay(containing: $0, calendar: .syntheticFund) })).sorted()
    }

    /// Accepts each company the intake rated hot as a deal, once, through the app's own "New deal from this".
    private static func acceptHotCandidates(
        of intake: HelperModel, on days: [WorkDay], in session: AppSession
    ) async throws -> Int {
        let now = session.store.clock()
        let read = try days.flatMap { try session.store.queries.items(of: intake.spec.task, on: $0) }
        let hot = read.filter {
            $0.isListed(at: now) && intake.spec.triage(of: $0)?.rating == .hot
        }
        var companies: Set<String> = []
        for item in hot where companies.insert(item[intake.spec.title]).inserted {
            await session.deals.newDeal(from: item, of: intake)
        }
        return session.deals.deals.count
    }

    private static func cost(of session: AppSession) throws -> Double {
        try session.store.queries.runs().map(\.usage.costUSD).reduce(0, +)
    }

    /// The same steps as the onboarding screens: the partner's name, the team, the Fund template, then done. The Fund
    /// template reads no chat, so the chat machine comes from the gallery, as a person adds one.
    private static func startFundTeam(in session: AppSession) throws {
        session.identity.identity.name = SyntheticWhatsApp.partner
        session.team.template = .fund
        for _ in 0..<session.onboarding.screens.count where !session.onboarding.isFinished {
            if session.onboarding.screen == .team { session.team.team.name = "Northlake Capital (synthetic)" }
            session.onboarding.next()
        }
        guard session.onboarding.isFinished else { throw BuildFailure.missing("finished setup") }
        guard let chats = GalleryTemplate.of(id: MachineTemplate.team.id) else {
            throw BuildFailure.missing("gallery item \(MachineTemplate.team.id)")
        }
        try session.store.start(chats)
        session.crew.reload()
    }

    private static func machine(reading source: HelperSpec.Source, in session: AppSession) throws -> HelperModel {
        guard let found = session.crew.machines.first(where: { $0.spec.source == source }) else {
            throw BuildFailure.missing("machine that reads \(source)")
        }
        return found
    }

    private static func mail(of helper: HelperModel) throws -> MailSource {
        guard let source = helper.source as? MailSource else { throw BuildFailure.missing("mail source") }
        return source
    }

    private static func chooseChat(of helper: HelperModel) throws -> WhatsAppChat {
        guard let source = helper.source as? WhatsAppSource else { throw BuildFailure.missing("WhatsApp source") }
        try source.loadGroups()
        guard let group = source.groups.first(where: { $0.jid == SyntheticWhatsApp.groupJID }) else {
            throw BuildFailure.missing("synthetic group")
        }
        try source.choose(group)
        return group
    }
}

extension Calendar {
    /// The calendar of the synthetic fund, in India: its chat lines, mails and held-out window are dated there.
    static let syntheticFund: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
