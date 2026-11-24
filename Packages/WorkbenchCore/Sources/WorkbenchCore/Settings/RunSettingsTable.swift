import Foundation

extension RunSettings {
    private static let trustSim =
        "trust-sim TRUST-1/TRUST-2, 2026-11-23, seed 20261123: per-run false-earned 6.6/6.7/7.0% at concentration 2/10/1000, the null at the 0.10 bar"
    private static let driftSim =
        "DriftSimulation, 2026-11-23: drift 0.05 to 0.25 found at a median of 34 audited runs (90th percentile 68); false alarm 0.2% at a stable 0.05; delta 0.1 gave 78.8% false alarms"
    private static let modelSearch =
        "S1 through ModelSearch, 30 dev claims, 2026-11-23: 0.0558 USD a search, median 11.0 s, low effort, 22/30 recall"

    /// Each number with its default, unit, kind and what measured it. The default is read from `standard`.
    public static var table: [Row] {
        let none = unmeasured
        return [
            row("pickChance", \.pickChance, "chance per item", .tuning, trustSim),
            row("allowedWrong", \.allowedWrong, "share of facts", .tuning, none),
            row("confidence", \.confidence, "certainty", .tuning, none),
            row("delta", \.delta, "false-alarm level", .tuning, driftSim),
            row("shareConfidence", \.shareConfidence, "certainty", .tuning, none),
            row("challengerLevel", \.challengerLevel, "e-process level", .tuning, none),
            row("heldOutTenths", \.heldOutTenths, "tenths of days", .tuning, none),
            row("minimumWrongToImprove", \.minimumWrongToImprove, "wrong marks", .tuning, none),
            row("improvementGrowthCharacters", \.improvementGrowthCharacters, "characters", .tuning, none),
            row("wrongExampleShare", \.wrongExampleShare, "share of examples", .tuning, none),
            row("charactersPerRequest", \.charactersPerRequest, "characters", .tuning, none),
            row("contextLines", \.contextLines, "lines", .tuning, none),
            row("openFactsShown", \.openFactsShown, "facts per machine", .tuning, none),
            row("objectsShownPerType", \.objectsShownPerType, "objects per type", .tuning, none),
            row("toldBeforeDays", \.toldBeforeDays, "days", .tuning, none),
            row("briefLines", \.briefLines, "lines", .tuning, none),
            row("summaryDetails", \.summaryDetails, "details", .tuning, none),
            row("proposalDays", \.proposalDays, "days", .tuning, none),
            row("proposals", \.proposals, "machines", .tuning, none),
            row("machineBriefCharacters", \.machineBriefCharacters, "characters", .tuning, none),
            row("draftWords", \.draftWords, "words", .tuning, none),
            row("callPointsFewest", \.callPointsFewest, "points", .tuning, none),
            row("callPointsMost", \.callPointsMost, "points", .tuning, none),
            row("askHits", \.askHits, "entries", .tuning, none),
            row("quoteWords", \.quoteWords, "words", .tuning, none),
            row("articleCharacters", \.articleCharacters, "characters", .tuning, none),
            row("newsRetentionDays", \.newsRetentionDays, "days", .tuning, none),
            row("sessionJoinSeconds", \.sessionJoinSeconds, "seconds", .tuning, none),
            row("sessionShortestSeconds", \.sessionShortestSeconds, "seconds", .tuning, none),
            row("queriesPerRuleFewest", \.queriesPerRuleFewest, "queries per rule", .tuning, none),
            row("queriesPerRule", \.queriesPerRule, "queries per rule", .tuning, none),
            row("hitsPerQuery", \.hitsPerQuery, "hits", .tuning, none),
            row("pagesPerRun", \.pagesPerRun, "pages", .tuning, none),
            row("pageCharacters", \.pageCharacters, "characters", .tuning, none),
            row("claimQueries", \.claimQueries, "queries per claim", .tuning, none),
            row("claimPages", \.claimPages, "pages per claim", .tuning, none),
            row("modelSearchUSD", \.modelSearchUSD, "USD per search", .tuning, modelSearch),
            row("braveSearchUSD", \.braveSearchUSD, "USD per search", .tuning, none),
            row("exaSearchUSD", \.exaSearchUSD, "USD per search", .tuning, none),
            row("firstGuessPerPageUSD", \.firstGuessPerPageUSD, "USD per page", .tuning, none),
            row("firstGuessPerCallUSD", \.firstGuessPerCallUSD, "USD per call", .tuning, none),
            row("typicalQueriesPerRule", \.typicalQueriesPerRule, "queries per rule", .tuning, none),
            row("timerStaleSeconds", \.timerStaleSeconds, "seconds", .tuning, none),
            row("timerCatchUpLimit", \.timerCatchUpLimit, "timers per pass", .tuning, none),
            row("timeOutRetries", \.timeOutRetries, "retries", .tuning, none),
            row("retryWindowSeconds", \.retryWindowSeconds, "seconds", .tuning, none),
            row("limitWithoutResetSeconds", \.limitWithoutResetSeconds, "seconds", .tuning, none),
            row("firstLookDays", \.firstLookDays, "days", .tuning, none),
            row("backlogCutoffDays", \.backlogCutoffDays, "days", .tuning, none),
            row("morningHour", \.morningHour, "hour of the day", .tuning, none),
            row("morningLastHour", \.morningLastHour, "hour of the day", .tuning, none),
            row("grantLifetimeSeconds", \.grantLifetimeSeconds, "seconds", .policy, none),
            row("captureRetentionDays", \.captureRetentionDays, "days", .policy, none),
            row("dayStartHour", \.dayStartHour, "hour of the day", .policy, none),
            row("revisitDays", \.revisitDays, "days", .policy, none),
            row("revisitMonths", \.revisitMonths, "months", .policy, none),
            row("timeOffsetDays", \.timeOffsetDays, "days", .bound, none),
            row("timeOffsetMinutes", \.timeOffsetMinutes, "minutes", .bound, none),
            row("timeYears", \.timeYears, "years", .bound, none),
            row("mailCharacters", \.mailCharacters, "characters", .bound, none),
            row("deckChunkBytes", \.deckChunkBytes, "bytes", .bound, none),
            row("deckChunks", \.deckChunks, "chunks", .bound, none),
            row("imageTextCharacters", \.imageTextCharacters, "characters", .bound, none),
            row("readablePageCharacters", \.readablePageCharacters, "characters", .bound, none),
        ]
    }

    private static func row<Value>(
        _ name: String, _ path: KeyPath<RunSettings, Value>, _ unit: String, _ kind: Kind, _ measuredOn: String
    ) -> Row {
        Row(
            name: name, value: "\(standard[keyPath: path])", unit: unit, kind: kind, measuredOn: measuredOn,
            isSaved: Saved.allCases.contains { $0.rawValue == name })
    }
}
