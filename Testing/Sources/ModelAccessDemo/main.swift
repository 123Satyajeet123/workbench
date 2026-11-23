import AgentCLI
import AppKit
import Foundation
import SwiftUI
import Synchronization

@testable import WorkbenchCore
@testable import WorkbenchUI

// Shows the gates of step F1 on made-up data. A fake launcher answers with recorded `auth status` JSON, the store is a
// scratch folder, and nothing touches the network, the Keychain or ~/Library/Application Support/Workbench.
// Usage: model-access [png-folder]
setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let pngFolder = URL(filePath: CommandLine.arguments.dropFirst().first ?? "/tmp/model-access")
var failures = 0

func check(_ condition: Bool, _ words: String) {
    if !condition { failures += 1 }
    print("  \(condition ? "yes" : "NO ") \(words)")
}

func gate(_ name: String, _ body: () async throws -> Void) async {
    print("\n\(name)")
    do { try await body() } catch {
        failures += 1
        print("  NO  stopped: \(error)")
    }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "model-access-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

/// Answers `auth status` with recorded JSON, `--version` with a version line, and a call with a valid claude answer.
final class RecordedLauncher: ProcessLauncher, Sendable {
    let authStatus: String
    private let launched = Mutex<[ProcessPlan]>([])
    init(authStatus: String) { self.authStatus = authStatus }
    var plans: [ProcessPlan] { launched.withLock { $0 } }

    func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput {
        launched.withLock { $0.append(plan) }
        switch plan.arguments.first {
        case "auth": return ProcessOutput(stdout: authStatus)
        case "--version": return ProcessOutput(stdout: "2.1.4 (Claude Code)\n")
        default:
            return ProcessOutput(
                stdout: #"{"type":"result","is_error":false,"structured_output":{"label":"yes"}}"#)
        }
    }
}

let maxPlan = """
    {"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"made.up@example.test",
     "orgId":"org-0000","orgName":"Made Up Org","subscriptionType":"max","planTier":"max_5x",
     "loginExpiresAt":"2027-01-15T10:00:00Z","analyticsDisabled":true,"newKeyFromTheFuture":7}
    """
let signedOut = #"{"loggedIn":false,"authMethod":"none","apiProvider":"firstParty"}"#
let apiKeySignIn = #"{"loggedIn":true,"authMethod":"api_key","apiProvider":"firstParty","orgId":"org-0000"}"#

func installedClaude(in folder: URL) throws -> [String: String] {
    let bin = folder.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let tool = bin.appending(path: "claude")
    FileManager.default.createFile(
        atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    return ["PATH": bin.path, "HOME": folder.path, "ANTHROPIC_API_KEY": "sk-made-up", "CLAUDE_CODE_X": "1"]
}

func probe(_ authStatus: String, installed: Bool, name: String) async throws -> (ReaderStatus, RecordedLauncher) {
    let folder = scratch.appending(path: name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let environment = installed ? try installedClaude(in: folder) : ["PATH": "/nonexistent", "HOME": folder.path]
    let launcher = RecordedLauncher(authStatus: authStatus)
    let reader = ReaderProbe(
        launcher: launcher, environment: environment, home: folder, workDirectory: folder.appending(path: "work"))
    return (await reader.status(), launcher)
}

await gate("G1 ReaderStatus from the CLI, with no model call") {
    let (plan, launcher) = try await probe(maxPlan, installed: true, name: "plan")
    check(plan.signedIn == true && plan.authMethod == "claude.ai", "signed in with a plan: \(plan.authMethod ?? "-")")
    check(plan.subscriptionType == "max" && plan.planTier == "max_5x", "plan max, tier max_5x")
    check(plan.version == "2.1.4" && plan.installedAt?.lastPathComponent == "claude", "version 2.1.4, path found")
    check(plan.loginExpiresAt == (try? Date("2027-01-15T10:00:00Z", strategy: .iso8601)), "login expiry read")
    check(
        launcher.plans.map(\.arguments) == [["auth", "status", "--json"], ["--version"]],
        "only auth status and version ran: \(launcher.plans.map { $0.arguments.joined(separator: " ") })")
    check(
        launcher.plans.allSatisfy {
            $0.environment.keys.allSatisfy { !$0.hasPrefix("ANTHROPIC") && !$0.hasPrefix("CLAUDE_CODE") }
        },
        "the shell's keys never reached the process")
    check(
        !"\(plan)".contains("made.up") && !"\(plan)".contains("org-0000") && !"\(plan)".contains("Made Up"),
        "email, org id and org name are not in the status")
    let out = try await probe(signedOut, installed: true, name: "out").0
    check(out.signedIn == false && out.subscriptionType == nil && out.planTier == nil, "signed out: no plan fields")
    let key = try await probe(apiKeySignIn, installed: true, name: "key").0
    check(key.authMethod == "api_key" && key.subscriptionType == nil, "API key method: no plan guessed")
    let missing = try await probe(maxPlan, installed: false, name: "missing")
    check(missing.0 == .notInstalled && missing.1.plans.isEmpty, "missing CLI: not installed, no process started")
    let odd = try await probe("not json", installed: true, name: "odd").0
    check(
        odd.signedIn == nil && odd.authMethod == nil && odd.installedAt != nil,
        "unreadable output: not known, never a guess")
    let partial = ReaderStatus.parse(
        authStatus: Data(#"{"loggedIn":"yes","loginExpiresAt":"soon","planTier":3}"#.utf8), installedAt: nil,
        version: nil)
    check(partial.signedIn == nil && partial.loginExpiresAt == nil && partial.planTier == nil, "wrong types: not known")
}

func runner(
    _ launcher: RecordedLauncher, apiKey: String?, folder: URL, kind: AgentCLIKind = .claude
) -> AgentRunner {
    AgentRunner(
        kind: kind, model: "sonnet", effort: "low", timeout: .seconds(5), launcher: launcher,
        executable: URL(filePath: "/opt/fake/claude"), environment: [:], apiKey: apiKey, requiresAPIKey: apiKey != nil,
        workDirectory: folder.appending(path: "work"))
}

nonisolated struct Verdict: Decodable, Sendable { let label: String }

func ask(_ model: RecordedModel) async -> String {
    do {
        _ = try await model.generate(
            Verdict.self, schema: .object([.init("label", .string)]), task: "demo", instructions: "Say yes.",
            input: "made-up input", holding: [])
        return "ran"
    } catch { return "refused: \(error.localizedDescription)" }
}

await gate("G2 The gate, both ways") {
    let store = try Store(directory: scratch.appending(path: "store"))
    let launcher = RecordedLauncher(authStatus: maxPlan)
    let plan = RecordedModel(runner(launcher, apiKey: nil, folder: scratch), store: store)
    let before = try await ask(plan)
    check(before.hasPrefix("refused") && launcher.plans.isEmpty, "plan, no confirmation: \(before.prefix(48))...")
    check(try store.queries.runs().isEmpty, "no run row, no process started")

    try store.confirmModelTerms()
    check(await ask(plan) == "ran" && launcher.plans.count == 1, "plan, confirmed: runs, one process")
    check(try store.queries.runs().count == 1, "one run row")

    try store.keepModelTermsConfirmation(
        ModelTermsConfirmation(conditionsVersion: ModelTerms.currentVersion - 1, billing: "plan", confirmedAt: .now))
    check((await ask(plan)).hasPrefix("refused") && launcher.plans.count == 1, "confirmation of older words: refused")

    try store.confirmModelTerms()
    check(await ask(plan) == "ran" && launcher.plans.count == 2, "confirmed again: runs")
    try store.withdrawModelTerms()
    check((await ask(plan)).hasPrefix("refused") && launcher.plans.count == 2, "withdrawn: refused again")
    check(try store.queries.runs().count == 2, "refusals left no run row")

    let keyLauncher = RecordedLauncher(authStatus: maxPlan)
    let byKey = RecordedModel(runner(keyLauncher, apiKey: "sk-made-up", folder: scratch), store: store)
    check(await ask(byKey) == "ran" && keyLauncher.plans.count == 1, "API key, no confirmation: runs")
    let codex = RecordedModel(
        runner(RecordedLauncher(authStatus: maxPlan), apiKey: nil, folder: scratch, kind: .codex), store: store)
    check((await ask(codex)).hasPrefix("refused"), "Codex sign-in, no confirmation: refused")
    print("  conditions: \(ModelTerms.conditions.joined(separator: " | "))")
}

await gate("Settings › Model render") {
    let store = try Store(directory: scratch.appending(path: "render"))
    let (status, _) = try await probe(maxPlan, installed: true, name: "render-probe")
    let rows = Form { ModelReaderRows(store: store, kind: .claude, readStatus: { _ in status }) }.formStyle(.grouped)
    let host = NSHostingView(rootView: rows.frame(width: 560, height: 330).environment(\.colorScheme, .light))
    host.frame = CGRect(x: 0, y: 0, width: 560, height: 330)
    let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try FileManager.default.createDirectory(at: pngFolder, withIntermediateDirectories: true)
    let file = pngFolder.appending(path: "settings-model.png")
    try (bitmap.representation(using: .png, properties: [:]) ?? Data()).write(to: file)
    print("  png \(file.path)")
}

print(failures == 0 ? "\nAll gates held." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
