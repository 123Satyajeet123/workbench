import AppKit
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The inspector drawn for each state it has, in light and dark, at two zooms and the two ends of its width. The
/// folder comes from `INSPECTOR_SHOTS_DIR`, else the temporary folder.
@MainActor @Suite struct InspectorRenderTests {
    private struct Case {
        let name: String
        let proof: ProofContent
        var history: [String] = ["Found by Pip v3 on Thu 20 Nov.", "You marked it right on Fri.", "Due Fri 28 Nov."]
        var isHistoryOpen = false
        var offersDeals = false
    }

    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func fact(_ quote: String, span: QuoteSpan? = nil) -> Item {
        Item(
            id: 1, task: HelperSpec.team.task, day: WorkDay(containing: at), scope: teamJID, source: .whatsapp,
            citeFirst: 12, citeLast: 12, start: at, end: at,
            fields: ["person": "Aditya", "project": "Fund X raise", "text": "Aditya will send the deck to Fund X"],
            quote: quote, run: 1, quoteSpan: span)
    }

    private func lines(_ texts: [String], cited: Int, of item: Item) -> ProofContent {
        .lines(
            texts.enumerated().map { index, text in
                ProofEntry(
                    ChatLine(
                        id: 10 + Int64(index), time: at.addingTimeInterval(Double(index - cited) * 60), text: text,
                        isCited: index == cited),
                    of: item, DateWords(now: at))
            })
    }

    private func span(_ quote: String, in text: String) -> QuoteSpan {
        let words = Array(String(text.drop { $0 != ":" }.dropFirst(2)).nfc.unicodeScalars)
        let wanted = Array(quote.nfc.unicodeScalars)
        let start = (0...(words.count - wanted.count)).first { words[$0..<($0 + wanted.count)] == wanted[...] }!
        return QuoteSpan(line: 12, part: 0, start: start, end: start + wanted.count)
    }

    private var cases: [(Case, Item)] {
        let one = fact("deck bhej dunga Friday tak")
        let partText = "Aditya: Haan boss, deck bhej dunga Friday tak, bas Fund X ka term sheet dekh lun pehle 🙏"
        let part = fact("deck bhej dunga Friday tak", span: span("deck bhej dunga Friday tak", in: partText))
        let longText =
            "Meera: Boss, kal ki call ke baad maine socha ki designers ko Friday ko call karna theek rahega, "
            + "lekin pehle offer letter ka draft final karna padega, फिर हम तीनों शॉर्टलिस्ट वालों को एक साथ बुलाएँगे "
            + "aur salary band par baat karenge, warna baad mein dikkat hogi 🙏🏽 please confirm kar dena."
        let long = fact(longText.drop { $0 != ":" }.dropFirst(2).description)
        let missing = fact("deck bhej dunga")
        let hindi = fact("कल सुबह तक deck भेज दूँगा 🙏🏽")
        let noQuote = fact("")
        return [
            (Case(name: "one-line", proof: lines(["Aditya: deck bhej dunga Friday tak"], cited: 0, of: one)), one),
            (
                Case(
                    name: "five-lines-partial-quote",
                    proof: lines(
                        [
                            "Shivansh: deck ka kya status hai?", "Shivansh: investors ko kal bhejna hai", partText,
                            "Founder: 👍", "Aditya: ok",
                        ], cited: 2, of: part), isHistoryOpen: true, offersDeals: true), part
            ),
            (
                Case(name: "devanagari", proof: lines(["Aditya: कल सुबह तक deck भेज दूँगा 🙏🏽"], cited: 0, of: hindi)),
                hindi
            ),
            (Case(name: "no-quote", proof: .notice(InspectorWords.notFound)), noQuote),
            (Case(name: "loading", proof: .loading(rows: 5)), one),
            (Case(name: "missing-source", proof: .notice(InspectorWords.notFound)), missing),
            (
                Case(
                    name: "long-hinglish",
                    proof: lines(
                        ["Aditya: kal baat karte hain", longText, "Aditya: theek hai"], cited: 1, of: long)), long
            ),
            (
                Case(
                    name: "no-history", proof: lines(["Aditya: deck bhej dunga Friday tak"], cited: 0, of: one),
                    history: []), one
            ),
        ]
    }

    private func folder() throws -> URL {
        let url =
            ProcessInfo.processInfo.environment["INSPECTOR_SHOTS_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: ["light", "dark"], [1.0, 1.5])
    func theInspectorIsDrawnForEachStateInLightAndDarkAtTwoZoomsAndBothWidths(mode: String, zoom: Double) throws {
        let world = try DealFixture()
        let helper = try #require(world.crew.factKeepers.first)
        for (shot, item) in cases {
            for width in [320.0, 420.0] {
                let card = InspectorCard(
                    headline: FactHeadline(item: item, title: "Aditya will send the deck to Fund X by Friday"),
                    meta: "Fund X raise · due Fri 28 Nov",
                    source: InspectorWords.source(of: item, chat: "Founders group", DateWords(now: at)),
                    proof: shot.proof, history: shot.history)
                let view = InspectorContent(
                    item: item, card: card, helper: helper, surface: .machinePage, offersDeals: shot.offersDeals,
                    isHistoryOpen: shot.isHistoryOpen
                ) {
                    MarkBar(actions: [.done, .snooze(days: 1), .notRelevant, .wrong], act: { _ in })
                }
                .environment(ActionsModel(store: world.store, founder: { "Kabir" })).environment(world.deals)
                .frame(width: width).fixedSize(horizontal: false, vertical: true).zoomed(Zoom(zoom))
                let data = try renderedPNG(of: view.background(.pageFill), mode: mode)
                try data.write(to: folder().appending(path: "inspector-\(shot.name)-\(mode)-\(zoom)-\(Int(width)).png"))
                #expect(data.count > 5_000)
            }
        }
    }

    private func height(of view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 320).zoomed(Zoom(1)))
        return try #require(renderer.nsImage).size.height
    }

    @Test func theProofPlaceKeepsItsHeightWhenTheFiveLinesArrive() throws {
        let one = fact("deck bhej dunga Friday tak")
        let texts = (0..<5).map { "Aditya: line number \($0) of the chat" }
        let loaded = try height(of: ProofLines(content: lines(texts, cited: 2, of: one)))
        let loading = try height(of: ProofLines(content: .loading(rows: ProofModel.placeholderRows(for: one))))
        #expect(loading == loaded, "the proof place jumps when its lines arrive: \(loading) then \(loaded)")
        let fewer = try height(of: ProofLines(content: .loading(rows: 3)))
        #expect(fewer != loaded, "the height check can tell a short place from a full one")
    }
}
