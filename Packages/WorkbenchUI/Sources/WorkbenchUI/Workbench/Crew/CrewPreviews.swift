import SwiftUI
import WorkbenchCore

#Preview("Crew, a sample day") {
    ScratchSession { _ in
        CrewPage(open: { _ in }).frame(width: 860, height: 900)
    }
}

#Preview("A machine page, a sample day") {
    ScratchSession { session in
        if let pip = session.crew.machines.first(where: { $0.spec.task == HelperSpec.team.task }) {
            HelperPage(model: pip).frame(width: 860, height: 900)
        }
    }
}
