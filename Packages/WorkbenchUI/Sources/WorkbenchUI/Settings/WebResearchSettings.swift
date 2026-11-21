import Foundation
import Observation
import WebResearch
import WorkbenchCore

/// The founder's choices for web research: the search provider, its key and the monthly cap. The switch is the
/// consent kind `web` in the capture policy. The key lives in the Keychain only; the store holds the provider and the cap.
@Observable
final class WebResearchSettings {
    static let capChoices = [25, 50, 100, 250, 500]

    var provider: SearchProviderKind {
        didSet {
            save { $0.provider = provider }
            refreshKey()
        }
    }
    var monthlyCap: Int {
        didSet { save { $0.monthlyCap = monthlyCap } }
    }
    private(set) var hasKey = false
    private(set) var queriesThisMonth = 0
    let problems = ProblemSlot()

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let secrets: SecretStore

    init(store: Store, secrets: SecretStore = KeychainSecrets()) {
        self.store = store
        self.secrets = secrets
        let saved = (try? store.queries.webSettings()) ?? WebSettings()
        provider = saved.provider
        monthlyCap = saved.monthlyCap
        refreshKey()
        refreshUsage()
    }

    func key(for kind: SearchProviderKind) -> String? { secrets.read(kind.keyName) }

    func saveKey(_ key: String) {
        guard let key = key.cleaned else { return }
        problems.attempt("save the key", clearing: true) { try secrets.save(key, as: provider.keyName) }
        refreshKey()
    }

    func removeKey() {
        problems.attempt("remove the key", clearing: true) { try secrets.remove(provider.keyName) }
        refreshKey()
    }

    func refreshUsage() {
        queriesThisMonth = (try? store.queries.webQueriesSent(inMonthOf: store.clock())) ?? 0
    }

    /// A session for one check, opened through the consent gate: it throws a `WebBlock` and sends nothing when the
    /// consent is off, the key is missing or the cap is reached.
    func openSession() throws -> WebSession {
        defer { refreshUsage() }
        return try WebSession.open(
            store: store, key: { [secrets] in secrets.read($0.keyName) },
            make: { makeWebSession(provider: $0, key: $1, grant: $2) })
    }

    private func refreshKey() { hasKey = secrets.read(provider.keyName) != nil }

    private func save(_ change: (inout WebSettings) -> Void) {
        var settings = WebSettings(provider: provider, monthlyCap: monthlyCap)
        change(&settings)
        problems.attempt("save the web research settings", clearing: true) { try store.saveWebSettings(settings) }
    }
}
