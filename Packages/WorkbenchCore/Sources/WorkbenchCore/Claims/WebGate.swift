import Foundation
import GRDB

public enum WebBlock: Error, Equatable {
    case consentOff
    case noKey
    case capReached(cap: Int)
    case grantExpired
}

extension WebBlock: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .consentOff: "Web research is off. Nothing was sent. Switch it on in Settings to check claims."
        case .noKey: "Web research has no search key. Nothing was sent. Add the key in Settings."
        case .capReached(let cap): "The cap of \(cap) searches this month is reached. Nothing was sent."
        case .grantExpired: "The permission for this check ran out. Start the check again."
        }
    }
}

public struct WebSession: Sendable {
    let grant: CaptureGrant
    let cap: Int
    let store: Store
    let provider: any SearchProvider
    let pages: any PageFetching

    public static func open(
        store: Store, key: (SearchProviderKind) -> String?,
        make: (SearchProviderKind, String, CaptureGrant) -> (any SearchProvider, any PageFetching)
    ) throws -> WebSession {
        let now = store.clock()
        guard let grant = try store.currentPolicy().authorize(CaptureRequest(kind: .web), at: now).grant else {
            throw WebBlock.consentOff
        }
        let settings = try store.queries.webSettings()
        guard let secret = key(settings.provider)?.cleaned else { throw WebBlock.noKey }
        guard try store.queries.webQueriesSent(inMonthOf: now) < settings.monthlyCap else {
            throw WebBlock.capReached(cap: settings.monthlyCap)
        }
        let (provider, pages) = make(settings.provider, secret, grant)
        return WebSession(grant: grant, cap: settings.monthlyCap, store: store, provider: provider, pages: pages)
    }

    public func search(_ query: String, count: Int) async throws -> [SearchHit] {
        try ensureLive()
        guard try store.reserveWebQuery(cap: cap) else { throw WebBlock.capReached(cap: cap) }
        return try await provider.search(query, count: count)
    }

    public func fetch(_ url: URL) async throws -> FetchedPage {
        try ensureLive()
        return try await pages.fetch(url)
    }

    private func ensureLive() throws {
        guard grant.kind == .web, grant.expiresAt > store.clock() else { throw WebBlock.grantExpired }
    }
}

extension Store {
    static let webSettingsKey = "web.settings"

    public func saveWebSettings(_ settings: WebSettings) throws {
        try saveState(try Coding.json(settings), forKey: Self.webSettingsKey)
    }

    static func webQueryKey(_ date: Date) -> String { "web.queries." + String(date.stored.prefix(7)) }

    func reserveWebQuery(cap: Int) throws -> Bool {
        let now = clock()
        return try writer.write { db in
            let key = Self.webQueryKey(now)
            let sent =
                try Int.fetchOne(
                    db, sql: "SELECT CAST(value AS INTEGER) FROM state WHERE key = ?", arguments: [key]) ?? 0
            guard sent < cap else { return false }
            try db.execute(
                sql: """
                    INSERT INTO state(key, value, saved_at) VALUES (?,?,?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, saved_at = excluded.saved_at
                    """, arguments: [key, String(sent + 1), now.stored])
            return true
        }
    }
}

extension Queries {
    public func webSettings() throws -> WebSettings {
        try state(forKey: Store.webSettingsKey).flatMap { try? Coding.value(WebSettings.self, from: $0) }
            ?? WebSettings()
    }

    public func webQueriesSent(inMonthOf date: Date) throws -> Int {
        try state(forKey: Store.webQueryKey(date)).flatMap { Int($0) } ?? 0
    }
}
