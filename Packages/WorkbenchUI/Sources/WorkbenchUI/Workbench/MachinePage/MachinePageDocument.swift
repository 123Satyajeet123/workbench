import Foundation
import WorkbenchCore

/// What the words of the document's own fields do when the person edits them. The app that shows the page decides.
struct PageEdits {
    var rename: (String) -> Void = { _ in }
    var setJob: (String) -> Void = { _ in }
}

/// The blocks of a machine's page that are not stored on it: the title, the job and the machine's account of itself.
/// Each is worked out from the machine as it is now.
extension MachinePageModel {
    static let titleBlock = "document.title"
    static let jobBlock = "document.job"
    static let statusBlock = "document.status"

    var documentBlocks: DocumentBlocks {
        DocumentBlocks(head: [
            .field(id: Self.titleBlock, look: .title, hint: "Name this machine.", text: name),
            .field(id: Self.jobBlock, look: .body, hint: "Say what \(name) is for.", text: job ?? ""),
            .machine(id: Self.statusBlock, view: .status(statusRendering), standing: .live),
        ])
    }

    func edit(field block: String, to text: String) {
        switch block {
        case Self.titleBlock: edits.rename(text)
        case Self.jobBlock: edits.setJob(text)
        default: break
        }
    }

    private var statusRendering: StatusRendering {
        let notices = [ownerNotice, problems.text, helper.problem].compactMap { $0 }
        switch status(Date()) {
        case nil:
            return StatusRendering(notices: notices, reads: reads, sentence: "", journal: [], act: nil)
        case .failure(let error)?:
            return StatusRendering(
                notices: notices, reads: reads, sentence: "Could not read the status: \(error.localizedDescription)",
                journal: [], act: nil)
        case .success(let status)?:
            return StatusRendering(
                notices: notices, reads: reads, sentence: status.sentence, journal: status.latest?.lines ?? [],
                act: readAction)
        }
    }

    private var readAction: ActionLink? {
        let canRead = helper.phase != .reading && !helper.source.hasNothingToRead && !helper.isPaused
        return canRead ? ActionLink(name: .read, label: helper.spec.source.readVerb) : nil
    }
}

extension MachinePageModel {
    /// Shows the machine's account of itself again: now, then every minute, and every two seconds while a reading runs.
    func keepStatusFresh() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: helper.phase == .reading ? .seconds(2) : .seconds(60))
        }
    }
}
