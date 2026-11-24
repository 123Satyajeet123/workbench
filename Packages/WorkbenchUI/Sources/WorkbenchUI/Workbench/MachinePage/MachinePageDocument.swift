import Foundation
import WorkbenchCore

/// What the words of the document's own fields and settings do when the person edits them. The app that shows the
/// page decides.
struct PageEdits {
    var rename: (String) -> Void = { _ in }
    var setJob: (String) -> Void = { _ in }
    var setPaused: (Bool) -> Void = { _ in }
}

/// The blocks of a machine's page that are not stored on it: the title, the job and the machine's account of itself
/// above the page's own blocks, and below them how the machine works. Each is worked out from the machine as it is now.
extension MachinePageModel {
    static let titleBlock = "document.title"
    static let jobBlock = "document.job"
    static let statusBlock = "document.status"
    static let moreBlock = "document.more"
    static let howBlock = "document.how"
    static let readsBlock = "document.reads"
    static let briefBlock = "document.brief"
    static let settingsBlock = "document.settings"
    static let criteriaBlock = "document.criteria"

    var documentBlocks: DocumentBlocks {
        DocumentBlocks(
            head: [
                .field(id: Self.titleBlock, look: .title, hint: "Name this machine.", text: name),
                .field(id: Self.jobBlock, look: .body, hint: "Say what \(name) is for.", text: job ?? ""),
                .machine(id: Self.statusBlock, view: .status(statusRendering), standing: .live),
            ], tail: tail)
    }

    private var tail: [PageBlockData] {
        var blocks: [PageBlockData] = [
            line(Self.howBlock, .heading(text: "How \(name) works")),
            line(
                Self.readsBlock,
                .line(
                    LineRendering(
                        text: "Reads: \(reads).",
                        act: link(.choose, "Change what it reads")))),
            line(Self.briefBlock, .text(text: spec.brief, cites: [])),
            line(
                Self.briefBlock + ".edit",
                .line(
                    LineRendering(
                        text: "This is what \(name) is told when it reads.",
                        act: link(.brief, "Edit the brief")))),
            line(Self.settingsBlock, .settings(SettingsRendering(sentences: settingSentences))),
        ]
        if let rules = spec.criteria?.rules.count {
            blocks.append(
                line(
                    Self.criteriaBlock,
                    .line(
                        LineRendering(
                            text: "Criteria: \(rules) \(rules == 1 ? "rule" : "rules").",
                            act: link(.criteria, "Edit…")))))
        }
        blocks.append(
            line(
                Self.moreBlock,
                .line(
                    LineRendering(
                        text: "Marks, trials, sharing and what each source sends:",
                        act: link(.more, "Open them")))))
        return blocks
    }

    /// A phrase the person may click. A page that is read-only offers none: everything they open writes.
    private func link(_ name: OpenTarget.Action, _ label: String) -> ActionLink? {
        owner == nil ? nil : ActionLink(name: name, label: label)
    }

    private func line(_ id: String, _ view: MachineView) -> PageBlockData {
        .machine(id: id, view: view, standing: .live)
    }

    // MARK: Fields

    func edit(field block: String, to text: String) {
        switch block {
        case Self.titleBlock: edits.rename(text)
        case Self.jobBlock: edits.setJob(text)
        default: break
        }
    }

    // MARK: Status

    private var statusRendering: StatusRendering {
        let waiting = proposal.map { "\(name) has a change for this page. \($0.note)" }
        let notices =
            [ownerNotice, problems.text, helper.problem, waiting, isAsking ? "\(name) is working on it…" : nil]
            .compactMap { $0 } + refusals.map(\.description)
        switch status(Date()) {
        case nil:
            return StatusRendering(notices: notices, sentence: "", journal: [], act: nil)
        case .failure(let error)?:
            return StatusRendering(
                notices: notices, sentence: "Could not read the status: \(error.localizedDescription)",
                journal: [], act: nil)
        case .success(let status)?:
            return StatusRendering(
                notices: notices, sentence: status.sentence, journal: status.latest?.lines ?? [],
                act: readAction)
        }
    }

    private var readAction: ActionLink? {
        let canRead = helper.phase != .reading && !helper.source.hasNothingToRead && !helper.isPaused
        return canRead ? link(.read, helper.spec.source.readVerb) : nil
    }

    /// Shows the machine's account of itself again: now, then every minute, and every two seconds while a reading runs.
    func keepStatusFresh() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: helper.phase == .reading ? .seconds(2) : .seconds(60))
        }
    }

    // MARK: What a click does

    func act(_ action: OpenTarget.Action) {
        switch action {
        case .read: Task { await helper.read() }
        case .more: isShowingMore = true
        case .brief: isEditingBrief = true
        case .criteria: isEditingCriteria = true
        case .choose:
            choosing = PickerKind.allCases.first { PickerChoice.unavailableNote($0, for: helper) == nil }
            isShowingMore = choosing == nil
        case .accept: Task { await accept() }
        case .decline: discard()
        case .undo: undoSetting()
        }
    }

    // MARK: Headings

    /// A heading the person retyped. Words that name only what the machine has become the view they name, with no
    /// model call; any other words are the person's request to the machine, and a request it refuses leaves the words as
    /// the heading with a note that says so.
    func edit(heading id: String, to text: String) {
        guard owner != nil, let block = MachineBlockID(id), let words = text.cleaned else { return }
        problems.attempt("change the heading") {
            guard case .facts(let view)? = try store.queries.page(of: page, for: viewer).page.blocks[block],
                view.title != words
            else { return }
            let gate = PageGate(catalog: PageCatalog(spec: spec, items: facts))
            if let resolved = gate.view(named: words, from: view, of: spec) {
                headingNotes[id] = nil
                try store.replaceBlock(block, with: .facts(resolved))
            } else {
                Task { await askAbout(block, view, words) }
            }
        }
    }

    private func askAbout(_ block: MachineBlockID, _ view: FactsView, _ words: String) async {
        let isProposed = await ask("Change the view titled \u{201C}\(view.title)\u{201D} to match: \(words)")
        guard !isProposed else { return }
        var named = view
        named.title = words
        problems.attempt("keep the heading") {
            let place = try store.queries.page(of: page, for: viewer).page.order.firstIndex(of: .machine(block))
            try store.replaceBlock(block, with: .facts(named))
            guard let place,
                case .machine(let replacement)? = try store.queries.page(of: page, for: viewer).page.order[safe: place]
            else { return }
            headingNotes[replacement.rawValue] = "\(name) did not understand this heading, so it only names the view."
        }
        refresh()
    }

    // MARK: Settings

    private var settingSentences: [SettingsRendering.Sentence] {
        var sentences = [
            sentence(
                "machine", [.words("\(name) is "), choice("machine.on", helper.isPaused ? "off" : "on"), .words(".")])
        ]
        if helper.isOutbound {
            sentences.append(
                sentence(
                    "weekly",
                    [
                        .words("Finds startups every week while Workbench is open: "),
                        choice("weekly.on", on(helper.weekly.isOn)),
                    ]
                ))
        } else {
            let watch = helper.watch
            sentences.append(
                sentence(
                    "watch",
                    [
                        .words("Reads new \(spec.source.lineNoun) by itself: "), choice("watch.on", on(watch.isOn)),
                        .words(". Every "), number("watch.every", watch.everyMinutes), .words(" minutes, from "),
                        number("watch.from", watch.fromHour), .words(" to "), number("watch.until", watch.untilHour),
                        .words("."),
                    ]))
        }
        if spec.nudge != nil {
            let nudge = helper.nudge
            sentences.append(
                sentence(
                    "nudge",
                    [
                        .words("Reminds people at "),
                        .chip(
                            "nudge.time", text: SettingEdit.words(hour: nudge.hour, minute: nudge.minute),
                            entry: .time),
                        .words(" who wrote nothing: "), choice("nudge.on", on(nudge.isOn)), .words("."),
                    ]))
        }
        return sentences
    }

    private func sentence(_ id: String, _ parts: [SettingsRendering.Part]) -> SettingsRendering.Sentence {
        let note = settingNote.flatMap { $0.sentence == id ? $0 : nil }
        return SettingsRendering.Sentence(
            parts: parts, note: note?.text ?? "",
            act: note != nil && settingUndo != nil ? link(.undo, "Undo") : nil)
    }

    private func on(_ isOn: Bool) -> String { isOn ? "on" : "off" }

    private func choice(_ key: String, _ now: String) -> SettingsRendering.Part {
        .chip(key, text: now, entry: .choice, choices: ["on", "off"])
    }

    private func number(_ key: String, _ now: Int) -> SettingsRendering.Part {
        .chip(key, text: String(now), entry: .number)
    }

    /// How a value reads now, so a change can be told and taken back; nil for a key the page does not have.
    private func value(of key: String) -> String? {
        switch key {
        case "machine.on": helper.isPaused ? "off" : "on"
        case "watch.on": on(helper.watch.isOn)
        case "watch.every": String(helper.watch.everyMinutes)
        case "watch.from": String(helper.watch.fromHour)
        case "watch.until": String(helper.watch.untilHour)
        case "nudge.on": on(helper.nudge.isOn)
        case "nudge.time": SettingEdit.words(hour: helper.nudge.hour, minute: helper.nudge.minute)
        case "weekly.on": on(helper.weekly.isOn)
        default: nil
        }
    }

    /// A value the person typed into a chip. The record changes only when the value is valid for it; otherwise the
    /// sentence says why and the record stays.
    func edit(setting key: String, to text: String) {
        guard owner != nil, let before = value(of: key),
            let sentenceID = key.split(separator: ".").first.map(String.init)
        else { return }
        do {
            try apply(key, text)
            let now = value(of: key) ?? before
            settingUndo = now == before ? settingUndo : (key, before)
            settingNote = (sentenceID, now == before ? "" : "Changed from \(before) to \(now).")
        } catch let refusal as SettingEdit.Refusal {
            settingNote = (sentenceID, "\(refusal.reason) Nothing changed.")
        } catch {
            settingNote = (sentenceID, "Could not save this: \(error.localizedDescription)")
        }
    }

    private func undoSetting() {
        guard let (key, old) = settingUndo else { return }
        settingUndo = nil
        let sentenceID = key.split(separator: ".").first.map(String.init) ?? key
        do {
            try apply(key, old)
            settingNote = (sentenceID, "Changed back to \(old).")
        } catch {
            settingNote = (sentenceID, "Could not change it back: \(error.localizedDescription)")
        }
    }

    private func apply(_ key: String, _ text: String) throws {
        switch key {
        case "machine.on": edits.setPaused(!(try SettingEdit.onOff(text)))
        case "watch.on": helper.watch.isOn = try SettingEdit.onOff(text)
        case "weekly.on": helper.weekly.isOn = try SettingEdit.onOff(text)
        case "nudge.on":
            let isOn = try SettingEdit.onOff(text)
            Task { await helper.setNudge(on: isOn) }
        case "watch.every":
            helper.watch.everyMinutes = try SettingEdit.number(
                text, in: SettingEdit.minutes, of: "Minutes between readings")
        case "watch.from":
            let hour = try SettingEdit.number(text, in: SettingEdit.hours, of: "The first hour")
            guard hour < helper.watch.untilHour else {
                throw SettingEdit.Refusal(reason: "Reading must start before it ends.")
            }
            helper.watch.fromHour = hour
        case "watch.until":
            let hour = try SettingEdit.number(text, in: 1...24, of: "The last hour")
            guard hour > helper.watch.fromHour else {
                throw SettingEdit.Refusal(reason: "Reading must end after it starts.")
            }
            helper.watch.untilHour = hour
        case "nudge.time":
            let time = try SettingEdit.time(text)
            helper.nudge.hour = time.hour
            helper.nudge.minute = time.minute
        default: break
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
