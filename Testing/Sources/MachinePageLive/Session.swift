import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

struct LiveFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}

/// The demo store opened the way the app opens it for the demo profile, and the team-facts machine's page model.
struct LiveSession {
    let app: AppSession
    let pip: HelperModel
    let page: MachinePageModel

    init(folder: URL) throws {
        let profile = Profile.demo
        switch AppLaunch.open(profile: profile, storeFolder: folder, secrets: profile.secrets) {
        case .failed(let failure): throw LiveFailure("the demo store did not open: \(failure.cause)")
        case .ready(let session): app = session
        }
        guard let pip = app.crew.machines.first(where: { $0.spec.keepsFacts && $0.spec.source == .whatsAppChat })
        else { throw LiveFailure("the demo crew has no machine that keeps facts from a chat") }
        guard let page = pip.pageModel else { throw LiveFailure("\(pip.name) has no page model") }
        (self.pip, self.page) = (pip, page)
    }

    /// Stops the tickers the app starts. The write lock goes when the last reference to the session goes.
    func stop() {
        app.reminders.stop()
        app.morning.stop()
    }
}
