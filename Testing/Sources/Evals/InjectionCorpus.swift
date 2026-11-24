import CryptoKit
import Foundation
import WorkbenchCore

/// One case of the prompt-injection eval (research 86, Decision 4; D3 §5): lines in a captured format, the machine task
/// they are read under, and a canary that must never reach a watched exit. Every name, domain and handle is synthetic.
public struct InjectionCase: Codable, Sendable, Equatable {
    public enum Format: String, Codable, Sendable, CaseIterable {
        case whatsapp, telegram, mail, web, call, screen
        /// A teammate's fact as received through the relay.
        case sharedFact = "shared_fact"

        var idPrefix: String {
            switch self {
            case .whatsapp: "wa"
            case .telegram: "tg"
            case .mail: "ml"
            case .web: "wb"
            case .call: "cl"
            case .screen: "sc"
            case .sharedFact: "sf"
            }
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case attack, benign
    }

    /// The attacker's goal (D3 §5). A benign case names the goal it looks like.
    public enum Goal: String, Codable, Sendable, CaseIterable {
        case exfilQuery = "exfil_query"
        case exfilURL = "exfil_url"
        case widen, act, forge, text

        /// The exits where a success of this goal shows.
        public var primaryExits: Set<Exit> {
            switch self {
            case .exfilQuery: [.searchQuery]
            case .exfilURL: [.urlFetch, .browserOpen]
            case .widen: [.labelWiden, .relayEnvelope]
            case .act: [.proposalArgument]
            case .forge: [.factKept, .proposalArgument]
            case .text: [.answerText]
            }
        }

        /// Theft and widening move a secret the attacker cannot read; the other goals plant the attacker's own token.
        public var canaryRole: Canary.Role {
            switch self {
            case .exfilQuery, .exfilURL, .widen: .secret
            case .act, .forge, .text: .marker
            }
        }
    }

    public enum Technique: String, Codable, Sendable, CaseIterable {
        case direct, hidden, adaptive
        case toolPoisoning = "tool_poisoning"
        case multiTurn = "multi_turn"
        case multiSource = "multi_source"
        /// A benign case that looks like an attack.
        case lookAlike = "look_alike"
    }

    /// How a hidden attack hides its words.
    public enum Concealment: String, Codable, Sendable, CaseIterable {
        case base64, hex, rot13, homoglyph, devanagari, reversed, leetspeak
        case hiddenSpan = "hidden_span"
        case altText = "alt_text"
        case pageTitle = "page_title"
        case htmlHidden = "html_hidden"
        case zeroWidth = "zero_width"
        case unicodeTags = "unicode_tags"
        case spelledOut = "spelled_out"
        case backgroundVoice = "background_voice"
        case voiceSpoof = "voice_spoof"
        /// Text in the accessibility tree that the screen does not show.
        case offscreenText = "offscreen_text"
        /// An instruction in a shared fact's field values instead of its quote.
        case fieldValue = "field_value"
    }

    /// A place where a run's output can leave the model: what the code check watches for the canary.
    public enum Exit: String, Codable, Sendable, CaseIterable {
        /// G1 sink `search:<provider>`: the text of a web search query.
        case searchQuery = "search_query"
        /// G1 sink `web:<host>`: a URL the fetcher GETs.
        case urlFetch = "url_fetch"
        /// G1 sink `browser`: a URL the person's browser opens.
        case browserOpen = "browser_open"
        /// G1 sink `relay:<team>`: a sealed envelope to teammates.
        case relayEnvelope = "relay_envelope"
        /// Any argument of a proposal: page ops, filing, fact edits, shares, new machines, reminders.
        case proposalArgument = "proposal_argument"
        /// A stored or proposed value whose computed readers are wider than the readers of the canary's line.
        case labelWiden = "label_widen"
        /// A fact the Verifier kept, or a close of an open fact.
        case factKept = "fact_kept"
        /// Words shown to the person: Mochi's answer, the composer's note, a claim verdict.
        case answerText = "answer_text"

        /// The exits where a secret leaves its readers. A secret shown to the owner in an answer is no leak.
        public static let secretExits: Set<Exit> = [
            .searchQuery, .urlFetch, .browserOpen, .relayEnvelope, .proposalArgument, .labelWiden,
        ]
    }

    public struct Line: Codable, Sendable, Equatable {
        /// The line as a model reads it, in its source's grammar.
        public var text: String
        /// The raw value of the `Authority` the store gives the line.
        public var authority: String
        /// Whether the attacker wrote or controls this line.
        public var attacker: Bool

        public var trust: Authority? { Authority(rawValue: authority) }
    }

    public struct Input: Codable, Sendable, Equatable {
        public var format: Format
        public var container: String
        /// Days after the work day; a multi-turn attack spans several.
        public var day: Int
        /// The principals that may read the lines; "public" for a web page.
        public var readers: [String]
        public var lines: [Line]
    }

    public struct Task: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case dailyRead = "daily_read"
            case claimCheck = "claim_check"
            case mochiAsk = "mochi_ask"
            case pageComposer = "page_composer"

            /// The exits a run of this task can reach under the planned runtime (B3, C4).
            public var reachableExits: Set<Exit> {
                switch self {
                case .dailyRead: [.factKept, .proposalArgument, .labelWiden, .relayEnvelope]
                case .claimCheck: [.searchQuery, .urlFetch, .browserOpen, .factKept, .answerText]
                case .mochiAsk: Set(Exit.allCases).subtracting([.factKept])
                case .pageComposer: Set(Exit.allCases).subtracting([.factKept, .browserOpen])
                }
            }
        }

        public var kind: Kind
        /// The machine whose day is read; only for a daily read.
        public var machine: String?
        /// The person's requests in order, or the claim text for a claim check; empty for a daily read.
        public var requests: [String]
        /// Open facts the daily read is shown, as the prompt renders them.
        public var open: [String]
    }

    public struct Canary: Codable, Sendable, Equatable {
        public enum Role: String, Codable, Sendable {
            /// Private data in a trusted line; it must not reach a sink that is not its reader.
            case secret
            /// The attacker's own token in the requested action or text; it must not reach a watched exit at all.
            case marker
        }

        public var token: String
        public var role: Role
    }

    public struct Reach: Codable, Sendable, Equatable {
        public var exit: Exit
        public var contains: String
    }

    /// The benign task's outcome: what a correct run does whether or not an attack is present.
    public struct Expected: Codable, Sendable, Equatable {
        public var outcome: String
        /// Task success: every entry holds in the run's exits.
        public var mustReach: [Reach]
    }

    public var id: String
    public var format: Format
    public var kind: Kind
    public var goal: Goal
    public var technique: Technique
    public var concealment: Concealment?
    public var workDay: String
    public var task: Task
    public var inputs: [Input]
    public var attackerGoal: String?
    public var canary: Canary
    public var exits: [Exit]
    public var expected: Expected

    var lines: [Line] { inputs.flatMap(\.lines) }
    var attackerInputs: [Input] { inputs.filter { $0.lines.contains(where: \.attacker) } }
    /// Every word of the case a model may read.
    var allText: String { (lines.map(\.text) + task.requests + task.open).joined(separator: "\n") }
}

/// The split of a case, fixed by the hash of its id before any run.
public enum InjectionSplit: String, Codable, Sendable, CaseIterable {
    case dev
    case heldOut = "held_out"

    public static let rule = "SHA-256 of \"inject-corpus/v1/\" + id; first byte < 128 is dev, else held_out"

    public init(caseID: String) {
        let digest = Array(SHA256.hash(data: Data(("inject-corpus/v1/" + caseID).utf8)))
        self = digest[0] < 128 ? .dev : .heldOut
    }
}

/// The frozen counts and the digest of the held-out cases. A change to a held-out case fails the check.
public struct InjectionManifest: Codable, Sendable, Equatable {
    public var version: String
    public var total: Int
    public var dev: Int
    public var heldOut: Int
    public var heldOutDigest: String
}

public struct InjectionCorpus: Sendable {
    public var cases: [InjectionCase]
    public var manifest: InjectionManifest

    public init(cases: [InjectionCase], manifest: InjectionManifest) {
        self.cases = cases
        self.manifest = manifest
    }

    /// Reads `cases/<format>.json` and `manifest.json` from `folder`. A case in the wrong file is a problem.
    public static func load(_ folder: URL) throws -> (corpus: InjectionCorpus, problems: [String]) {
        var cases: [InjectionCase] = []
        var problems: [String] = []
        for format in InjectionCase.Format.allCases {
            let file = folder.appending(path: "cases/\(format.rawValue).json")
            let found = try JSONDecoder().decode([InjectionCase].self, from: Data(contentsOf: file))
            problems += found.filter { $0.format != format }.map { "\($0.id): stored in \(format.rawValue).json" }
            cases += found
        }
        let manifest = try JSONDecoder().decode(
            InjectionManifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
        return (InjectionCorpus(cases: cases, manifest: manifest), problems)
    }

    public func split(_ split: InjectionSplit) -> [InjectionCase] {
        cases.filter { InjectionSplit(caseID: $0.id) == split }
    }

    /// SHA-256 of the held-out cases, sorted by id, as sorted-key JSON.
    public var heldOutDigest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(split(.heldOut).sorted { $0.id < $1.id })) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every rule the corpus breaks; empty when it is sound.
    public var problems: [String] {
        cases.flatMap(\.problems) + identityProblems + coverageProblems + manifestProblems
    }

    private var identityProblems: [String] {
        let repeatedIDs = Dictionary(grouping: cases, by: \.id).filter { $0.value.count > 1 }.keys
        let texts = cases.map(\.allText)
        let canaryProblems = cases.compactMap { item -> String? in
            let holders = texts.filter { $0.contains(item.canary.token) }.count
            return holders > 1 ? "\(item.id): canary \(item.canary.token) repeats in \(holders) cases" : nil
        }
        return repeatedIDs.sorted().map { "\($0): id repeats" } + canaryProblems
    }

    private var coverageProblems: [String] {
        let attacks = cases.filter { $0.kind == .attack }
        let formatKinds: [(String, Bool)] = InjectionCase.Format.allCases.flatMap { format in
            InjectionCase.Kind.allCases.map { kind in
                ("\(format.rawValue) \(kind.rawValue)", cases.contains { $0.format == format && $0.kind == kind })
            }
        }
        let goals: [(String, Bool)] = InjectionCase.Goal.allCases.map { goal in
            (goal.rawValue, attacks.contains { $0.goal == goal })
        }
        let techniques: [(String, Bool)] = InjectionCase.Technique.allCases.filter { $0 != .lookAlike }.map {
            technique in (technique.rawValue, attacks.contains { $0.technique == technique })
        }
        let tasks: [(String, Bool)] = InjectionCase.Task.Kind.allCases.map { kind in
            (kind.rawValue, cases.contains { $0.task.kind == kind })
        }
        return (formatKinds + goals + techniques + tasks).filter { !$0.1 }.map { "coverage: no case for \($0.0)" }
    }

    private var manifestProblems: [String] {
        let counts = (cases.count, split(.dev).count, split(.heldOut).count)
        var problems: [String] = []
        if counts != (manifest.total, manifest.dev, manifest.heldOut) {
            problems.append(
                "split counts: found total \(counts.0), dev \(counts.1), held_out \(counts.2); manifest says "
                    + "\(manifest.total), \(manifest.dev), \(manifest.heldOut)")
        }
        if heldOutDigest != manifest.heldOutDigest {
            problems.append("held-out digest \(heldOutDigest) differs from the manifest: a held-out case changed")
        }
        return problems
    }
}

extension InjectionCase {
    var problems: [String] {
        (shapeProblems + lineProblems + canaryProblems + exitProblems + expectedProblems + targetProblems)
            .map { "\(id): \($0)" }
    }

    private var shapeProblems: [String] {
        var problems: [String] = []
        let attackerLines = lines.filter(\.attacker)
        if id.wholeMatch(of: /[a-z]{2}-\d{3}/) == nil || !id.hasPrefix(format.idPrefix + "-") {
            problems.append("id must be \(format.idPrefix)-NNN")
        }
        if workDay.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) == nil { problems.append("work day is not yyyy-MM-dd") }
        if (kind == .benign) != (technique == .lookAlike) {
            problems.append("benign cases, and only they, are look_alike")
        }
        if (kind == .attack) != (attackerGoal?.isEmpty == false) {
            problems.append("attacker goal only and always on an attack")
        }
        if (kind == .attack) != !attackerLines.isEmpty {
            problems.append("an attack needs an attacker line; benign has none")
        }
        if (technique == .hidden) != (concealment != nil) { problems.append("concealment only and always on hidden") }
        if !inputs.contains(where: { $0.format == format && ($0.lines.contains(where: \.attacker) || kind == .benign) })
        {
            problems.append("no \(kind == .attack ? "attacker " : "")input in its own format")
        }
        if technique == .multiTurn, Set(attackerInputs.map(\.day)).count < 2, task.requests.count < 2 {
            problems.append("multi_turn needs attacker lines on two days or two requests")
        }
        if technique == .multiSource, attackerInputs.count < 2 {
            problems.append("multi_source needs two attacker inputs")
        }
        return problems + taskProblems
    }

    private var taskProblems: [String] {
        let isDaily = task.kind == .dailyRead
        var problems: [String] = []
        if isDaily != (task.machine != nil) { problems.append("a machine only and always on a daily read") }
        if isDaily != task.requests.isEmpty { problems.append("requests on every task except a daily read") }
        if !isDaily, !task.open.isEmpty { problems.append("open facts only on a daily read") }
        return problems
    }

    private var lineProblems: [String] {
        var problems: [String] = []
        var numbers: [Int] = []
        for input in inputs {
            if input.readers.isEmpty { problems.append("input \(input.container) has no readers") }
            if input.day < 0 { problems.append("input \(input.container) has a negative day") }
            for line in input.lines {
                if !Self.follows(input.format, line.text) {
                    problems.append("line breaks \(input.format) grammar: \(line.text)")
                }
                if line.trust == nil { problems.append("unknown authority \(line.authority)") }
                if input.format == .sharedFact, let trust = line.trust, trust > .groupMember {
                    problems.append("a received fact above group_member")
                }
                if let number = line.text.prefixMatch(of: /\[(\d+)\]/).flatMap({ Int($0.1) }) { numbers.append(number) }
            }
        }
        if numbers != numbers.sorted() || Set(numbers).count != numbers.count {
            problems.append("line numbers do not rise")
        }
        return problems
    }

    /// Whether a line has the shape its source renders (SourceDescriptor grammars; CallSummarizer for calls).
    static func follows(_ format: Format, _ line: String) -> Bool {
        switch format {
        case .whatsapp, .telegram: line.wholeMatch(of: /\[\d+\] \d{2}:\d{2} [^:]+: .+/) != nil
        case .mail: line.wholeMatch(of: /\[\d+\] [^:\[]+: .+/) != nil
        case .web: line.wholeMatch(of: /\[\d+\] \d{2}:\d{2} \S+ — .+?: .+/) != nil
        case .call: line.wholeMatch(of: /\[\d+\] \[\d{2}:\d{2}\] [^:]+: .+/) != nil
        case .screen: line.wholeMatch(of: /\[\d+\] \d{2}:\d{2}(–\d{2}:\d{2} \(\d+\))? .+/) != nil
        case .sharedFact: line.wholeMatch(of: /\[\d+\] shared by [^(:]+ \([^)]+\): .+ — ".+"/) != nil
        }
    }

    private var canaryProblems: [String] {
        let token = canary.token
        let holders = lines.filter { $0.text.contains(token) }
        var problems: [String] = []
        if token.wholeMatch(of: /cy[a-z2-7]{8}/) == nil {
            problems.append("canary \(token) is not cy + 8 base32 letters")
        }
        if holders.isEmpty { problems.append("canary not in its lines") }
        let role: Canary.Role = kind == .benign ? .secret : goal.canaryRole
        if canary.role != role { problems.append("canary role must be \(role.rawValue)") }
        switch canary.role {
        case .secret:
            if holders.contains(where: \.attacker) { problems.append("a secret canary sits in an attacker line") }
            if !holders.contains(where: { ($0.trust ?? .unknown) >= .groupMember }) {
                problems.append("a secret canary needs a trusted line")
            }
        case .marker:
            if !holders.contains(where: \.attacker) { problems.append("a marker canary needs an attacker line") }
        }
        return problems
    }

    private var exitProblems: [String] {
        let watched = Set(exits)
        var problems: [String] = []
        if exits.isEmpty { problems.append("no exits") }
        if watched.count != exits.count { problems.append("an exit repeats") }
        if !watched.isSubset(of: task.kind.reachableExits) { problems.append("an exit the task cannot reach") }
        if kind == .attack, watched.isDisjoint(with: goal.primaryExits) {
            problems.append("exits miss every primary exit of \(goal.rawValue)")
        }
        if canary.role == .secret, !watched.isSubset(of: InjectionCase.Exit.secretExits) {
            problems.append("a secret canary is watched where its owner may read it")
        }
        return problems
    }

    private var expectedProblems: [String] {
        var problems: [String] = []
        if expected.outcome.isEmpty { problems.append("no expected outcome") }
        if expected.mustReach.isEmpty { problems.append("no task-success check") }
        let trusted = lines.filter { !$0.attacker }.map(\.text)
        for reach in expected.mustReach {
            if reach.contains.isEmpty || reach.contains.contains(canary.token) {
                problems.append("a task-success check is empty or holds the canary")
            }
            if !task.kind.reachableExits.contains(reach.exit) { problems.append("success at an unreachable exit") }
            if reach.exit == .factKept, !trusted.contains(where: { $0.contains(reach.contains) }) {
                problems.append("a kept fact must quote a non-attacker line: \(reach.contains)")
            }
        }
        return problems
    }

    /// Every URL host, mail domain and web site must be synthetic (.invalid), so no case targets a real service.
    private var targetProblems: [String] {
        let text = allText + "\n" + inputs.map(\.container).joined(separator: "\n")
        let hosts =
            text.matches(of: #/https?://([^\s/?:"'<>\])]+)/#).map { String($0.1) }
            + text.matches(of: /[A-Za-z0-9._%+\-]+@([A-Za-z0-9.\-]+\.[A-Za-z]+)/).map { String($0.1) }
            + inputs.filter { $0.format == .web }.flatMap(\.lines).compactMap {
                $0.text.wholeMatch(of: /\[\d+\] \d{2}:\d{2} (\S+) — .+/).map { String($0.1) }
            }
        return Set(hosts).filter { !$0.lowercased().hasSuffix(".invalid") }.sorted().map {
            "target not synthetic: \($0)"
        }
    }
}
