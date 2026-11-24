import Foundation

/// Every number the app tunes, in one value. A person or an eval may change the four trust numbers; the store keeps
/// them (`Store.saveRunSettings`). Every other number is the default written here. `table` names each number with its
/// unit, its kind and what measured it. Criteria hold their own levels and cuts: this value does not repeat them.
public struct RunSettings: Codable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// A number to tune.
        case tuning
        /// A rule the person sets. Nobody tunes it.
        case policy
        /// A limit on what the model may say, or on what code may read. Nobody tunes it.
        case bound
    }

    public struct Row: Sendable, Equatable {
        public let name: String
        public let value: String
        public let unit: String
        public let kind: Kind
        public let measuredOn: String
        public let isSaved: Bool
    }

    public static let standard = RunSettings()
    public static let unmeasured = "home-made, unmeasured"

    enum Saved: String, CodingKey, CaseIterable {
        case pickChance, allowedWrong, confidence, delta
    }

    // MARK: Trust (saved)

    /// The chance each new item has of being asked about. A stated design number; its false-earned rate is measured.
    public var pickChance = 0.15
    /// The wrong rate a certificate bets against. A stated target, not a fit.
    public var allowedWrong = 0.1
    /// The confidence a certificate asks for. A stated target, not a fit.
    public var confidence = 0.9
    /// The drift alarm's false-alarm level.
    public var delta = 0.001

    // MARK: Trust (code defaults)

    /// The confidence of the `share` rung, a level of 0.05.
    public var shareConfidence = 0.95
    public var challengerLevel = 0.10
    public var heldOutTenths = 3
    public var minimumWrongToImprove = 3
    public var improvementGrowthCharacters = 400
    public var wrongExampleShare = 0.5

    // MARK: What a reading shows the model

    public var charactersPerRequest = 40_000
    public var contextLines = 20
    public var openFactsShown = 300
    public var objectsShownPerType = 40
    public var toldBeforeDays = 14
    public var briefLines = 8
    public var summaryDetails = 5
    public var proposalDays = 3
    public var proposals = 5
    public var machineBriefCharacters = 160
    public var draftWords = 60
    public var callPointsFewest = 2
    public var callPointsMost = 5
    public var askHits = 30
    public var quoteWords = 25
    public var articleCharacters = 12_000
    public var newsRetentionDays = 30
    public var sessionJoinSeconds: TimeInterval = 120
    public var sessionShortestSeconds: TimeInterval = 10

    // MARK: Search and cost

    public var queriesPerRuleFewest = 3
    public var queriesPerRule = 5
    public var hitsPerQuery = 5
    public var pagesPerRun = 15
    public var pageCharacters = 12_000
    public var claimQueries = 3
    public var claimPages = 5
    public var modelSearchUSD = 0.0558
    public var braveSearchUSD = 0.005
    public var exaSearchUSD = 0.008
    public var firstGuessPerPageUSD = 0.02
    public var firstGuessPerCallUSD = 0.02
    public var typicalQueriesPerRule = 4

    // MARK: Time and failure

    public var timerStaleSeconds: TimeInterval = 2 * 86_400
    public var timerCatchUpLimit = 5
    public var timeOutRetries = 1
    public var retryWindowSeconds = 10
    public var limitWithoutResetSeconds: TimeInterval = 3600
    public var firstLookDays = 30
    public var backlogCutoffDays = 7
    public var morningHour = 9
    public var morningLastHour = 11

    // MARK: Policy

    public var grantLifetimeSeconds: TimeInterval = 300
    public var captureRetentionDays = 30
    public var dayStartHour = 5
    public var revisitDays = 180
    public var revisitMonths = 6

    // MARK: Bounds

    public var timeOffsetDays = 365
    public var timeOffsetMinutes = 7 * 24 * 60
    public var timeYears = 2000...2100
    public var mailCharacters = 100_000
    public var deckChunkBytes = 512 * 1024
    public var deckChunks = 64
    public var imageTextCharacters = 2000
    public var readablePageCharacters = 500

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Saved.self)
        pickChance = try values.decodeIfPresent(Double.self, forKey: .pickChance) ?? pickChance
        allowedWrong = try values.decodeIfPresent(Double.self, forKey: .allowedWrong) ?? allowedWrong
        confidence = try values.decodeIfPresent(Double.self, forKey: .confidence) ?? confidence
        delta = try values.decodeIfPresent(Double.self, forKey: .delta) ?? delta
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Saved.self)
        try values.encode(pickChance, forKey: .pickChance)
        try values.encode(allowedWrong, forKey: .allowedWrong)
        try values.encode(confidence, forKey: .confidence)
        try values.encode(delta, forKey: .delta)
    }

    /// The wealth at which a certificate is earned.
    public var threshold: Double { 1 / (1 - confidence) }
    /// The weight of an answer with the least chance the weights allow.
    public var heaviestWeight: Double { 1 / pickChance }

    /// A saved number must keep the formulas that use it defined.
    func validated() throws -> RunSettings {
        for (name, value) in [
            ("pickChance", pickChance), ("allowedWrong", allowedWrong), ("confidence", confidence), ("delta", delta),
        ] where !(value > 0 && value < 1 || name == "pickChance" && value == 1) {
            throw StoreError.settingNotApplied("\(name) must be above 0 and below 1")
        }
        return self
    }
}

extension Int {
    /// The number as English words: 8 is "eight". A prompt says a count this way.
    var spelledOut: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
