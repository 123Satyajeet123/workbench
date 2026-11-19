import Foundation
import GoogleConnector
import Observation
import WorkbenchCore

/// The Google accounts, read from the Keychain once and again after a connect or disconnect. Every screen shares one.
@Observable
final class GoogleAccountsModel {
    private(set) var accounts: [String] = []
    private(set) var mailAllowed: Set<String> = []
    private(set) var readsLabelFor: Set<String> = []
    private(set) var problem: String?
    private(set) var isConnecting = false
    @ObservationIgnored private let connector: GoogleConnector?
    @ObservationIgnored private let store: Store?
    @ObservationIgnored private var signIn: Task<Void, Never>?

    private static let labelChoiceKey = "googleLabelReading"

    init(store: Store? = nil) {
        self.store = store
        do {
            connector = try GoogleConnector()
        } catch {
            connector = nil
            problem = error.localizedDescription
        }
        loadLabelChoice()
        refresh()
    }

    var canConnect: Bool { connector != nil }

    /// Workbench may read the mail of this account: Google allowed it, and the person has not turned it off.
    func readsLabel(of email: String) -> Bool { mailAllowed.contains(email) && readsLabelFor.contains(email) }

    func connect() {
        guard let connector else { return }
        authorize { _ = try await connector.connect() }
    }

    func setReadsLabel(_ on: Bool, of email: String) {
        guard on else {
            readsLabelFor.remove(email)
            saveLabelChoice()
            return
        }
        guard let connector else { return }
        guard !mailAllowed.contains(email) else {
            readsLabelFor.insert(email)
            saveLabelChoice()
            return
        }
        authorize {
            try await connector.enableWorkbenchLabel(for: email)
            self.readsLabelFor.insert(email)
            self.saveLabelChoice()
        }
    }

    func cancelConnect() {
        signIn?.cancel()
    }

    func disconnect(_ email: String) async {
        guard let connector else { return }
        do {
            problem = try await connector.disconnect(email)?.localizedDescription
        } catch {
            problem = error.localizedDescription
        }
        readsLabelFor.remove(email)
        saveLabelChoice()
        refresh()
    }

    private func authorize(_ work: @escaping () async throws -> Void) {
        guard !isConnecting else { return }
        isConnecting = true
        signIn = Task {
            do {
                try await work()
                problem = nil
            } catch {
                problem = Task.isCancelled ? nil : error.localizedDescription
            }
            isConnecting = false
            refresh()
        }
    }

    private func refresh() {
        do {
            accounts = try connector?.accounts() ?? []
            mailAllowed = Set(try accounts.filter { try connector?.gmailEnabled(for: $0) == true })
        } catch {
            problem = error.localizedDescription
        }
    }

    private func loadLabelChoice() {
        do {
            let text = try store?.queries.state(forKey: Self.labelChoiceKey)
            readsLabelFor = Set(try text.map { try JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? [])
        } catch {
            problem = error.localizedDescription
        }
    }

    private func saveLabelChoice() {
        guard let store else { return }
        do {
            let text = String(decoding: try JSONEncoder().encode(readsLabelFor.sorted()), as: UTF8.self)
            try store.saveState(text, forKey: Self.labelChoiceKey)
        } catch {
            problem = error.localizedDescription
        }
    }
}
