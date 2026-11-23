import AppKit
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Every onboarding screen drawn to a PNG for a person to look at, for each template. The folder comes from
/// `VC_PREVIEW_DIR`, else the temporary folder.
@Suite struct OnboardingRenderTests {
    private func session(_ template: TeamTemplate) throws -> AppSession {
        _ = NSApplication.shared
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            throw CocoaError(.fileReadUnknown)
        }
        session.team.template = template
        session.onboarding.identityModel.identity.name = "Rhea"
        session.team.team.name = "Brave Capital"
        return session
    }

    private func draw(_ screen: OnboardingScreen, of session: AppSession, as name: String) throws {
        let model = session.onboarding
        model.advance(to: screen)
        let rows = ConnectRow.rows(for: model.needs).filter { $0 != .reader }
        let facts = ConnectFacts(readerFound: true, mailOn: true, sourceRows: rows)
        let step = OnboardingStep(screen: screen, facts: facts).environment(session).environment(MacAccess())
        try renderPNG(step, named: name)
    }

    @Test(arguments: [TeamTemplate.fund, .startupTeam]) func everyScreenIsDrawnForATemplate(
        template: TeamTemplate
    ) throws {
        let session = try session(template)
        for screen in session.onboarding.screens where screen != .done {
            try draw(screen, of: session, as: "onboarding-\(template.id)-\(screen.rawValue)")
        }
        session.onboarding.advance(to: .done)
        try draw(.done, of: session, as: "onboarding-\(template.id)-done")
    }

    @Test func theSetupStepShowsAnAnswerKept() throws {
        let session = try session(.fund)
        let question = try #require(session.onboarding.questions.first { $0.kind == .criteria })
        session.onboarding.answer(question, with: .criteria(Criteria(rules: [], hotAt: 7)))
        try draw(.setup, of: session, as: "onboarding-fund-setup-answered")
    }

    @Test func aBlankTeamHasTheReaderOnlyAndNoSetupStep() throws {
        let session = try session(.blank)
        #expect(!session.onboarding.screens.contains(.setup))
        try draw(.connect, of: session, as: "onboarding-blank-connect")
        try draw(.done, of: session, as: "onboarding-blank-done")
    }
}
