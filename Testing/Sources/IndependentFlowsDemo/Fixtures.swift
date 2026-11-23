import AppKit
import CaptureService
import CoreText
import Foundation
import Kernel
import LocalSources
import SwiftUI
import Synchronization

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A model that answers with the next reply and remembers each input. A call to summarize a day is answered with no
/// summaries and is not counted. `@words@` in a reply becomes the number of the
/// input line that holds the words, as a model cites a line by what it says.
final class SequenceModel: StructuredModel, Sendable {
    let name = "scripted"
    private let replies: Mutex<[String]>
    let inputs = Mutex<[String]>([])

    init(_ replies: [String]) { self.replies = Mutex(replies) }

    func append(_ more: [String]) { replies.withLock { $0 += more } }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let isSummary = instructions == Summarizer.instructions
        if !isSummary { inputs.withLock { $0.append(input) } }
        let text =
            isSummary
            ? #"{"summaries":[]}"#
            : Self.cite(replies.withLock { $0.isEmpty ? "{}" : $0.removeFirst() }, in: input)
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(text.utf8)), model: "scripted-1",
            usage: Usage(inputTokens: 300, outputTokens: 40, costUSD: 0.02), reply: text)
    }

    static func cite(_ reply: String, in input: String) -> String {
        reply.replacing(#/@([^@"]+)@/#) { match in
            let words = String(match.output.1)
            let line = input.split(separator: "\n").first { $0.hasPrefix("[") && $0.contains(words) }
            return line.flatMap { $0.dropFirst().split(separator: "]").first }.map(String.init) ?? "0"
        }
    }
}

/// A search provider and page fetcher that answer from memory and remember each query.
final class FakeSearch: SearchProvider, PageFetching, Sendable {
    let queries = Mutex<[String]>([])
    static let article = URL(string: "https://news.example/acme")!

    func search(_ query: String, count: Int) async throws -> [SearchHit] {
        queries.withLock { $0.append(query) }
        return [SearchHit(title: "Acme", url: Self.article, snippet: "")]
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        FetchedPage(url: url, text: "Acme has raised $11 Mn in its seed funding round.")
    }
}

final class MemorySecrets: SecretStore, Sendable {
    let values = Mutex<[String: String]>([:])
    func read(_ name: String) -> String? { values.withLock { $0[name] } }
    func lookup(_ name: String) throws -> String? { values.withLock { $0[name] } }
    func create(_ value: String, as name: String) throws -> Bool {
        values.withLock { values in
            guard values[name] == nil else { return false }
            values[name] = value
            return true
        }
    }
    func save(_ value: String, as name: String) throws { values.withLock { $0[name] = value } }
    func remove(_ name: String) throws { values.withLock { $0[name] = nil } }
}

final class QuietNotifier: Notifier {
    var access = SystemAccess.allowed
    func authorize() async -> SystemAccess { access }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}

/// The store's clock, which a scene can set back to keep a message on the day it was written.
nonisolated final class SceneClock: Sendable {
    private let value = Mutex(Date.now)
    var now: Date { value.withLock { $0 } }
    func set(_ date: Date) { value.withLock { $0 = date } }
    func reset() { set(.now) }
}

/// A fund's store in a scratch folder: its machines made from the Fund template, a deals model, and a claims model
/// over a scripted model and a fake search. Nothing here touches the real store, the network or the Keychain.
@MainActor
final class Desk {
    static let owner = try! PersonID("demo-owner")

    let folder = FileManager.default.temporaryDirectory.appending(path: "flows-\(UUID().uuidString)")
    let store: Store
    let clock = SceneClock()
    let capture: CaptureService
    let crew: Crew
    let deals: DealsModel
    let claims: ClaimsModel
    let model: SequenceModel
    let search: FakeSearch

    init(template: TeamTemplate? = .fund, replies: [String] = [], whatsApp: URL? = nil) throws {
        let clock = clock
        let store = try Store(directory: folder, clock: { clock.now })
        let model = SequenceModel(replies)
        let search = FakeSearch()
        if let template { try store.startTeam(from: template) }
        let service = try CaptureService(store: store, owner: .success(Self.owner))
        let recorded = { (_: ModelChoice) in RecordedModel(model, store: store) }
        let crew = Crew(
            store: store, capture: service, founder: { "Aditya" }, makeModel: recorded, notifier: QuietNotifier(),
            whatsAppContainer: whatsApp ?? folder.appending(path: "no-whatsapp"))
        try store.saveWebSettings(WebSettings(provider: .brave, monthlyCap: 100))
        self.store = store
        self.model = model
        self.search = search
        self.crew = crew
        capture = service
        deals = DealsModel(
            store: store,
            catalog: TeamCatalogModel(store: store, crew: crew, author: { "Aditya" }, secrets: MemorySecrets()))
        claims = ClaimsModel(
            store: store, me: { "Aditya" }, web: WebResearchSettings(store: store, secrets: MemorySecrets()),
            owner: .success(Self.owner), makeModel: recorded,
            openSession: {
                try WebSession.open(store: store, key: { _ in "key" }, make: { _, _, _ in (search, search) })
            })
    }

    func allow(_ switches: [SourceKind: Bool], labels: [SourceKind: Set<String>] = [:]) throws {
        try capture.update {
            $0.switches = switches
            $0.allowList = labels
            $0.browsers = ["com.brave.Browser": "Brave Browser"]
        }
    }

    /// Onboarding over this store, as a new person meets it, with the chosen template.
    func onboarding(choosing template: TeamTemplate) -> OnboardingModel {
        let identity = IdentityModel(store: store)
        let model = OnboardingModel(
            store: store, identity: identity, team: TeamModel(store: store, me: { "Rhea" }),
            teamStarted: { [crew] in crew.reload() })
        model.teamModel.template = template
        identity.identity.name = "Rhea"
        model.teamModel.team.name = "Brave Capital"
        return model
    }

    /// A deal added by hand, as "Add deal" does.
    func newDeal(_ title: String) throws -> WorkObject {
        let id = try require(deals.create(title: title))
        return try require(deals.deal(id))
    }

    func close() { try? FileManager.default.removeItem(at: folder) }
}

func require<T>(_ value: T?) throws -> T {
    guard let value else { throw DemoError("a value the demo needs is missing") }
    return value
}

struct DemoError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func freshFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A one-page PDF with real text, as a founder's deck exports.
func deckPDF(lines: [String], named name: String) throws -> URL {
    let url = try freshFolder().appending(path: name)
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw DemoError("no PDF context") }
    context.beginPDFPage(nil)
    for (index, text) in lines.enumerated() {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)]))
        context.textPosition = CGPoint(x: 48, y: 720 - Double(index) * 32)
        CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return url
}

/// A PNG with text drawn in it, as a screenshot of a slide.
func slidePNG(_ text: String) throws -> URL {
    let image = NSImage(size: NSSize(width: 1000, height: 200))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1000, height: 200).fill()
    (text as NSString).draw(
        at: NSPoint(x: 30, y: 70),
        withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let url = try freshFolder().appending(path: "slide.png")
    let png = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())?.representation(using: .png, properties: [:])
    try (png ?? Data()).write(to: url)
    return url
}

/// Draws a view in a window as a person sees it and writes it to a PNG in `folder`. Returns the file. A view that loads
/// in a task gets a moment to finish first.
@discardableResult
func renderPNG(_ view: some View, named name: String, in folder: URL, width: CGFloat = 520) async throws -> URL {
    let framed = view.padding(Space.l).frame(width: width, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor)).environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: framed)
    host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: host.fittingSize.height))
    let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(400))
    host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: host.fittingSize.height))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw DemoError("no bitmap") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "\(name).png")
    let png = bitmap.representation(using: .png, properties: [:]) ?? Data()
    guard png.count > 10_000 else { throw DemoError("\(name) drew blank") }
    try png.write(to: file)
    return file
}
