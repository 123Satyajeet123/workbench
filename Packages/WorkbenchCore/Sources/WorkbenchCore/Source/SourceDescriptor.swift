import Foundation
import Kernel
import Lines

/// What one source of evidence is, as data: the facts every layer reads about it. The consent kind it needs, its name,
/// how the model reads its lines, how long they live, how it gives its text, what must hold before it reads, which
/// containers a person must name, which tables it forgets, and which kind of picker the person uses to choose what
/// it reads. A reader (`EvidenceSource`) carries one. A new source adds the fields it needs in the change that reads
/// them.
public struct SourceDescriptor: Sendable, Equatable {
    /// How long lines live. The raw value is the `retention_class` of the line.
    public enum Retention: String, Sendable { case chat, mail, page, file, note, screen, call, transient }

    /// How the source gives its text. The raw value is the `obtained_by` of the line.
    public enum Obtained: String, Sendable {
        case db
        /// A service the source asks for each message, such as Telegram.
        case api
        case domText = "dom_text"
        case axValue = "ax_value"
        /// Speech recognized on this Mac.
        case speech
    }

    /// What a person chooses on a machine's page to say what this source reads.
    public enum Picker: Sendable, Equatable {
        /// A chat or group.
        case chat
        /// A mail label.
        case mailLabel
        /// The sites a machine reads.
        case sites
        /// A file the person adds.
        case file
    }

    /// The source's own name, unique across sources: the key of its `SourceID`.
    public let key: String
    /// The name a machine's spec stores for this source, as written in rows that exist. Every stored name decodes.
    public let specName: String
    /// The source as a person names it: a heading in Settings and the start of a sentence.
    public let name: String
    /// Where a fact came from, as "Captured from ...".
    public let origin: String
    public let consent: SourceKind
    /// What the model is told about the lines it reads from this source. It holds the workspace profile's words as
    /// `{…}`; `WorkspaceProfile.render` fills them.
    public let grammar: String
    /// What one line of this source is, in a sentence such as "Read new messages every hour".
    public let lineNoun: String
    /// The words of the button that reads now.
    public let readVerb: String
    public let retention: Retention
    public let obtainedBy: Obtained
    /// How far before its last read a reader looks again for edited messages.
    public let editWindow: TimeInterval
    /// How many lines on each side of a line a fact cites belong to its evidence. Nil: the whole container, because
    /// the container is one subject, such as a mail thread.
    public let evidenceReach: Int?
    /// A group is read only while its audience is the one the person confirmed as all agreed. `Store.agree` records
    /// that audience, and a write whose audience differs is refused inside the write transaction.
    public let requiresAgreedAudience: Bool
    /// The source reads other people's words, so it reads only the containers the person named: one chat or one mail
    /// label, never all of them.
    public let requiresContainerAllowList: Bool
    /// The person wrote it. The capture switch and pause do not stop it, and age does not erase it. Only a label the
    /// person put on the deny list stops it, and only the person's delete erases it.
    public let ownWriting: Bool
    /// A machine over this source follows the companies the investor watches.
    public let followsCompanies: Bool
    /// A machine over this source finds new startups by web search, on a weekly schedule, instead of reading days.
    public let findsStartups: Bool
    /// How a fact from this source cites its lines: one line, or a run of lines when a fact joins consecutive ones.
    public let citation: HelperSpec.Citation
    /// How the person chooses what this source reads. Nil: the person does not choose on a page.
    public let picker: Picker?
    /// What must hold before this source can read, in the order Settings shows the problems. A source with none has no
    /// row of its own in the health list.
    public let needs: [HealthNeed]
    /// The rows this source keeps outside the evidence store, which a delete of its kind removes.
    public let forgets: Forgetting
    /// Sites that page capture never keeps, because this source reads them or the site bars readers.
    public let pageDenyHosts: Set<String>
    /// The sites and apps this source names by address or bundle id; empty for a source that has none.
    let callServices: CallServices

    init(
        key: String, specName: String? = nil, name: String, origin: String? = nil, consent: SourceKind, grammar: String,
        lineNoun: String = "lines", readVerb: String = "Read now", retention: Retention, obtainedBy: Obtained,
        editWindow: TimeInterval,
        evidenceReach: Int? = nil, requiresAgreedAudience: Bool = false, requiresContainerAllowList: Bool = false,
        ownWriting: Bool = false, followsCompanies: Bool = false, findsStartups: Bool = false,
        citation: HelperSpec.Citation = .one, picker: Picker? = nil, needs: [HealthNeed] = [],
        forgets: Forgetting = Forgetting(),
        pageDenyHosts: Set<String> = [], callServices: CallServices = CallServices(sites: [], apps: [:])
    ) {
        self.key = key
        self.specName = specName ?? key
        self.name = name
        self.origin = origin ?? name
        self.consent = consent
        self.grammar = grammar
        self.lineNoun = lineNoun
        self.readVerb = readVerb
        self.retention = retention
        self.obtainedBy = obtainedBy
        self.editWindow = editWindow
        self.evidenceReach = evidenceReach
        self.requiresAgreedAudience = requiresAgreedAudience
        self.requiresContainerAllowList = requiresContainerAllowList
        self.ownWriting = ownWriting
        self.followsCompanies = followsCompanies
        self.findsStartups = findsStartups
        self.citation = citation
        self.picker = picker
        self.needs = needs
        self.forgets = forgets
        self.pageDenyHosts = pageDenyHosts
        self.callServices = callServices
    }

    /// Whether any machine can read this source one work day of lines at a time. News and search fetch with a list of
    /// companies or a thesis of their own, which a machine made from only a job sentence does not have.
    public var givesDaysOfLines: Bool { !followsCompanies && !findsStartups }

    /// The id of this source for one owner. Two owners never share one.
    public func sourceID(owner: PersonID) throws(IdentifierError) -> SourceID {
        Kernel.Source(owner: owner, key: try SourceKey(key)).id
    }
}

/// A spec stores the name of its source and gets the descriptor back from the registry.
extension SourceDescriptor: Codable {
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let descriptor = SourceRegistry.descriptor(named: name) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "no source is named \(name)"))
        }
        self = descriptor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(specName)
    }
}

extension SourceDescriptor {
    private static let whatsAppGrammar = """
        one work day of a WhatsApp group. Each line is `[number] HH:mm sender: text`.{language note}
        """

    public static let whatsAppChat = SourceDescriptor(
        key: "whatsapp.chat", specName: "whatsapp_chat", name: "WhatsApp", consent: .whatsapp,
        grammar: whatsAppGrammar, lineNoun: "messages", retention: .chat, obtainedBy: .db,
        editWindow: Scan.chatEditWindow, evidenceReach: 20, requiresContainerAllowList: true, picker: .chat,
        needs: [.consent, .permission(.fullDiskAccess), .owner], pageDenyHosts: ["web.whatsapp.com"])
}

extension SourceDescriptor {
    private static let telegramGrammar = """
        one work day of a Telegram group. Each line is `[number] HH:mm sender: text`.{language note}
        """

    /// One Telegram group, read through the founder's own account. Telegram lets an app pass chat data to a model only
    /// when every person in the chat agrees, so a group is read only for the audience the founder confirmed.
    public static let telegramChat = SourceDescriptor(
        key: "telegram.chat", specName: "telegram_chat", name: "Telegram", consent: .telegram,
        grammar: telegramGrammar, lineNoun: "messages", retention: .chat, obtainedBy: .api, editWindow: 0,
        evidenceReach: 20, requiresAgreedAudience: true, requiresContainerAllowList: true, picker: .chat,
        needs: [.consent, .key(.telegramApp)])
}

extension SourceDescriptor {
    private static let gmailGrammar = """
        the mail threads {the occupation} opened in the label they named, in order. Each line is `[number] sender: the \
        text`. A line of an attached deck also names the file and the page: `sender — file page 3: the text`. A \
        thread shows one line for each message and each deck page.
        """

    /// Gmail read by the browser extension, one label at a time. The grant label is the Gmail label the person named.
    public static let gmailMail = SourceDescriptor(
        key: "mail.gmail", specName: "mail_threads", name: "Mail", consent: .mail, grammar: gmailGrammar,
        lineNoun: "messages", retention: .mail, obtainedBy: .domText, editWindow: 0,
        requiresContainerAllowList: true, picker: .mailLabel,
        needs: [.consent, .owner, .browser, .readerCurrent(.mail)],
        forgets: Forgetting(
            tables: [
                .init(name: "mail_part", ageColumn: "seen_at"),
                .init(name: "mail_open", ageColumn: "day", age: .day),
            ]),
        pageDenyHosts: [MailContext.site])
}

extension SourceDescriptor {
    private static let pageGrammar = """
        the text of web pages {the role} had on screen, in order. Each line is `[number] HH:mm site — page \
        title: the text on screen`. The same page can appear again after a scroll, with new text.
        """

    /// The text of web pages, read by the browser extension. The grant label is the site; the sites a machine reads are
    /// that machine's own choice among the sites the person allowed.
    public static let webPage = SourceDescriptor(
        key: "web.page", specName: "page_text", name: "Web pages", origin: "a page", consent: .screenText,
        grammar: pageGrammar, lineNoun: "pages", retention: .page, obtainedBy: .domText, editWindow: 0,
        picker: .sites, needs: [.consent, .owner, .browser, .readerCurrent(.otherSites)],
        forgets: Forgetting(activity: [.text, .page]))
}

extension SourceDescriptor {
    /// The words the person typed by hand: a claim on a deal, or a fact they added. The person's act is the consent.
    public static let typedNote = SourceDescriptor(
        key: "note.typed", name: "Typed by you", origin: "you", consent: .typed,
        grammar: """
            what the person typed by hand: a claim on a deal, or a fact they added. Each line is `[number] who: the \
            words`.
            """, retention: .file, obtainedBy: .db, editWindow: 0)

    /// A file the person added to a deal: the text of its pages. The person's act is the consent.
    public static let droppedFile = SourceDescriptor(
        key: "file.dropped", name: "A file you added", consent: .dropped,
        grammar: "a file the person added to a deal. Each line is `[number] who — file page N: the text`.",
        retention: .file, obtainedBy: .db, editWindow: 0, picker: .file)

    /// The connections in the person's own LinkedIn data export, one line for each. The person's act of choosing the
    /// file is the consent. The lines name third people, so only the person who chose the file reads them. LinkedIn's
    /// terms ban extensions that read its pages, so page capture never keeps its site.
    public static let linkedinExport = SourceDescriptor(
        key: "linkedin.export", name: "Your LinkedIn export", consent: .linkedinExport,
        grammar: """
            the people {the role} is connected to on LinkedIn, from {the role's} own data export. Each line is \
            `[number] name, position at company. connected on date. email. profile URL`; a part the export left empty \
            is missing.
            """, retention: .file, obtainedBy: .db, editWindow: 0, pageDenyHosts: ["linkedin.com"])

    private static let screenWindowGrammar = """
        the windows {the role} had in front, in order. Each line is `[number] HH:mm–HH:mm (minutes) app — window \
        title — address`; the address is a web page or a file and can be missing.
        """

    /// One stretch on one window, kept when it closes. The grant label is the app's bundle id.
    public static let screenWindow = SourceDescriptor(
        key: "screen.window", specName: "screen_sessions", name: "Screen", origin: "the screen", consent: .screen,
        grammar: screenWindowGrammar, lineNoun: "windows", retention: .screen, obtainedBy: .axValue, editWindow: 0,
        citation: .range, needs: [.consent, .permission(.accessibility)],
        forgets: Forgetting(activity: Activity.Kind.allCases.filter { $0 != .file }))

    private static let screenTextGrammar = """
        the text one window showed, one line for each line on screen. Each line is `[number] HH:mm text`.
        """

    /// The text a window showed at one walk. The grant label is the app's bundle id.
    public static let screenText = SourceDescriptor(
        key: "screen.text", name: "Screen", origin: "the screen", consent: .screen, grammar: screenTextGrammar,
        retention: .screen, obtainedBy: .axValue, editWindow: 0)

    private static let fileActivityGrammar = """
        the files {the role} had open. Workbench keeps one capture-log row for each; no machine reads them as lines.
        """

    /// The files the person had open, as rows of the capture log.
    public static let fileActivity = SourceDescriptor(
        key: "file.activity", name: "Files", consent: .files, grammar: fileActivityGrammar, retention: .screen,
        obtainedBy: .axValue, editWindow: 0, forgets: Forgetting(activity: [.file]))

    private static let calendarGrammar = """
        today's events in the calendars the person chose. Nothing is stored and no machine reads them as lines.
        """

    /// Today's events in the calendars the person chose, read through EventKit.
    public static let calendarEvent = SourceDescriptor(
        key: "calendar.event", name: "Calendar", consent: .calendar, grammar: calendarGrammar,
        retention: .transient, obtainedBy: .api, editWindow: 0)
}

extension SourceDescriptor {
    private static let newsGrammar = """
        one news article from a feed {the occupation} follows. The line is `[number] feed — title: text`. The Companies \
        list names the followed companies the article may be about.
        """

    /// Articles from the news feeds, read one at a time, only for companies the investor follows.
    public static let newsArticle = SourceDescriptor(
        key: "news.article", specName: "news_articles", name: "News", consent: .web, grammar: newsGrammar,
        lineNoun: "articles", readVerb: "Check the news", retention: .page, obtainedBy: .api,
        editWindow: 0, followsCompanies: true,
        forgets: Forgetting(tables: [.init(name: "news_article", ageColumn: "fetched_at")]))

    private static let webSearchGrammar = """
        one web page that a search found. The line is `[number] address — text`. It may name several startups, or \
        none.
        """

    /// Web pages found by search for the investor's criteria, read one at a time for startups that fit.
    public static let webSearch = SourceDescriptor(
        key: "web.search", specName: "web_search", name: "Web search", consent: .web, grammar: webSearchGrammar,
        lineNoun: "pages", readVerb: "Find startups", retention: .page, obtainedBy: .api,
        editWindow: 0, findsStartups: true,
        forgets: Forgetting(tables: [.init(name: "page_snapshot", ageColumn: "fetched_at")]))
}

/// The sources this build knows. A source starts only when a machine names it.
public enum SourceRegistry {
    public static let all: [SourceDescriptor] = [
        .whatsAppChat, .telegramChat, .gmailMail, .webPage, .typedNote, .droppedFile, .linkedinExport, .note,
        .screenWindow, .screenText, .fileActivity, .calendarEvent, .callTranscript, .webSearch, .newsArticle,
    ]

    /// The source with this key or the name a spec stores for it, or nil when no source has it.
    public static func descriptor(named name: String) -> SourceDescriptor? {
        all.first { $0.key == name || $0.specName == name }
    }

    /// The first source that reads under this consent kind, or nil when none does.
    public static func descriptor(consent: SourceKind) -> SourceDescriptor? { all.first { $0.consent == consent } }

    /// Every source that reads under this consent kind.
    public static func descriptors(consent: SourceKind) -> [SourceDescriptor] { all.filter { $0.consent == consent } }

    /// The sources that these names ask for, each once, in the order first named. A name no source has asks for
    /// nothing.
    public static func demanded(by names: some Sequence<String>) -> [SourceDescriptor] {
        var seen: Set<String> = []
        return names.compactMap { descriptor(named: $0) }.filter { seen.insert($0.key).inserted }
    }

    /// Whether a source of this kind reads only the containers the person named.
    public static func requiresContainerAllowList(_ kind: SourceKind) -> Bool {
        descriptors(consent: kind).contains(where: \.requiresContainerAllowList)
    }

    /// Whether this kind is the person's own writing.
    public static func isOwnWriting(_ kind: SourceKind) -> Bool {
        descriptors(consent: kind).contains(where: \.ownWriting)
    }

    /// The kinds of source a person can choose on a page.
    public static var pickable: Set<SourceKind> { Set(all.filter { $0.picker != nil }.map(\.consent)) }

    /// The sources that have a row in the health list, in the order Settings shows them.
    public static var withNeeds: [SourceDescriptor] { all.filter { !$0.needs.isEmpty } }
}
