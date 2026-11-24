import AppKit
import Foundation
import GRDB
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// What the page does with the store: a write that fails, a page the old editor wrote, a page no machine owns, and size.
extension Behaviour {
    private static let plainReady = "return window.wbEditor && document.querySelector('.bn-block-outer')"

    /// A write that cannot happen leaves the words in the editor and is tried again until the store has them.
    static func failedWrite() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let lock = try DatabaseQueue(path: desk.folder.appending(path: "workbench.sqlite").path)
        let held = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try? lock.write { _ in
                held.signal()
                release.wait()
            }
        }
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                held.wait()
                done.resume()
            }
        }
        try await session.place(desk.paragraphs[2])
        session.editor.insertText(" first")
        session.editor.insertText(" second")
        let failed = await waitUntilMain(seconds: 15) { session.controller.problem != nil }
        let problem = session.controller.problem ?? "none"
        let storedWhileLocked = try session.storedWords().last ?? ""
        let shownWhileLocked = try await session.filled().last ?? ""
        release.signal()
        let saved = await waitUntilMain(seconds: 15) {
            session.controller.problem == nil && ((try? session.storedWords().last) ?? "").hasSuffix("first second")
        }
        guard failed, saved, !shownWhileLocked.isEmpty, !storedWhileLocked.contains("first") else {
            throw DemoFailure(
                "failed \(failed) saved \(saved); stored while locked \"\(storedWhileLocked)\"; stored now \(try session.storedWords())"
            )
        }
        return
            "while the store was locked: problem = \"\(problem)\", store kept \"\(storedWhileLocked)\", editor kept \"\(shownWhileLocked.split(separator: "|").last ?? "")\"; after the lock went the page saved by itself, stored \"\(try session.storedWords().last ?? "")\", problem cleared"
    }

    fileprivate static func waitUntilMain(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Lines the old native editor wrote, with characters the new line format treats as marks, load with no write, and
    /// a change to one line rewrites no other line.
    static func oldNativePage() async throws -> String {
        let old = [
            "Budget talk with Asha Example.", "Total is 3 * 4 = 12 and the rest is TBD",
            "snake_case_name and _private_ marks",
            "- a dash at the start", "1. a number at the start", "# not a heading", "[draft] see (notes) and [x](y)",
            "   leading spaces stay", "a line with a trailing space ", "backslash \\ and `ticks` and ~tilde",
            "| a | b | table-like",
        ]
        let desk = try await Desk(texts: old)
        defer { desk.close() }
        let before = try desk.fingerprint()
        let session = try await Session(desk: desk, ready: plainReady)
        try await session.settle()
        guard try desk.fingerprint() == before, session.controller.storeWrites == 0 else {
            throw DemoFailure("loading wrote to the store")
        }
        let shown = try await session.editor.json(
            "return window.wbEditor.document.filter(b => b.type !== 'machine').map(b => b.type + ':' + (b.content || []).map(c => c.type === 'link' ? c.content.map(x => x.text).join('') : c.text + (Object.keys(c.styles).length ? '{' + Object.keys(c.styles).join('+') + '}' : '')).join(''))"
        )
        try await session.place(desk.paragraphs[0])
        session.editor.insertText(" Edited.")
        try await session.settle()
        let stored = try session.storedWords()
        guard stored.first == "Budget talk with Asha Example. Edited.",
            Array(stored.dropFirst()) == Array(old.dropFirst())
        else { throw DemoFailure("a change to line 1 rewrote others: \(stored)") }
        return
            "\(old.count) old lines loaded: store fingerprint equal, store writes = 0; editing line 1 changed only line 1 (the other \(old.count - 1) stored lines are byte-equal); the editor shows them as \(shown)"
    }

    /// A page no machine owns is a document too: the same controller, no machine blocks.
    static func plainPage() async throws -> String {
        let desk = try await Desk(plainPage: ["A plain page, written by hand."])
        defer { desk.close() }
        let session = try await Session(desk: desk, ready: plainReady)
        try await session.place(desk.paragraphs[0])
        session.editor.key("\r", code: 36)
        session.editor.insertText("# Second")
        try await session.settle()
        guard try session.storedWords() == ["A plain page, written by hand."] else {
            // The heading marker is typed text on a line that is not empty: it stays words, as typed.
            return try await plainResult(desk, session)
        }
        return try await plainResult(desk, session)
    }

    private static func plainResult(_ desk: Desk, _ session: Session) async throws -> String {
        let stored = try session.storedWords()
        try desk.reopen()
        let again = try await Session(desk: desk, ready: plainReady)
        let words = try await again.filled().count
        guard stored.count == 2, words == 2 else { throw DemoFailure("stored \(stored), shown \(words) blocks") }
        return "plain page: typed a second paragraph; stored \(stored); a restart shows \(words) blocks"
    }

    /// Load time and the time of one keystroke on pages of 200 and 2,000 paragraphs, with synthetic words.
    static func size() async throws -> String {
        var report: [String] = []
        for count in [200, 2000] {
            let texts = (1...count).map {
                "Paragraph \($0) of the synthetic page, with some words in it to fill a line."
            }
            let desk = try await Desk(texts: texts)
            defer { desk.close() }
            try desk.addMachineBlocks([(.heading("Synthetic"), after: .note(desk.paragraphs[0]))])
            let started = ContinuousClock.now
            let session = try await Session(
                desk: desk, ready: "return window.wbEditor && window.wbEditor.document.length >= \(count)")
            let load = started.duration(to: .now)
            try await session.editor.run(
                """
                window.__lat = []; let t0 = 0;
                document.addEventListener('beforeinput', () => { t0 = performance.now(); }, true);
                window.wbEditor.onChange(() => { const start = t0; setTimeout(() => window.__lat.push(performance.now() - start), 0); });
                """)
            try await session.place(desk.paragraphs[count / 2])
            for _ in 0..<30 {
                session.editor.insertText("x")
                try await Task.sleep(for: .milliseconds(80))
            }
            let latencies = try await session.editor.json("return window.__lat.slice(5).sort((a, b) => a - b)")
            let sorted = try JSONDecoder().decode([Double].self, from: Data(latencies.utf8))
            guard sorted.count >= 10 else {
                throw DemoFailure("only \(sorted.count) timed keystrokes for \(count) paragraphs")
            }
            let median = sorted[sorted.count / 2]
            let p95 = sorted[Int(Double(sorted.count) * 0.95)]
            let loadMs = Int(Double(load.components.seconds) * 1000 + Double(load.components.attoseconds) / 1e15)
            report.append(
                "\(count) paragraphs + 1 machine block: \(loadMs) ms from start to shown; one keystroke in the web process (input event to the page updated; no paint, the window is never shown) median \(String(format: "%.1f", median)) ms, p95 \(String(format: "%.1f", p95)) ms over \(sorted.count) keys"
            )
            try await session.settle()
        }
        return report.joined(separator: "; ") + " (synthetic words, off-screen window, debug build)"
    }
}

extension Behaviour {
    /// The editor reports the height of its page, which follows the page as it grows, and keeps no scroll bar of its own.
    static func height() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let host = session.editor.host
        _ = await waitUntilMain(seconds: 5) { host.height > 0 }
        let first = host.height
        try await session.place(desk.paragraphs[2])
        for line in 1...10 {
            session.editor.key("\r", code: 36)
            session.editor.insertText("Line \(line)")
        }
        let grew = await waitUntilMain(seconds: 5) { host.height > first + 200 }
        let page = try await session.editor.json(
            "return document.getElementById('page').getBoundingClientRect().height")
        let overflow = try await session.editor.json("return getComputedStyle(document.documentElement).overflow")
        guard grew, overflow == "\"hidden\"", abs((Double(page) ?? 0) - Double(host.height)) < 2 else {
            throw DemoFailure("height \(first) -> \(host.height), page \(page), overflow \(overflow)")
        }
        return
            "reported height \(Int(first)) pt for 3 paragraphs and 3 machine blocks, \(Int(host.height)) pt after 10 new lines (page element \(page) pt); the page's own overflow is \(overflow)"
    }
}
