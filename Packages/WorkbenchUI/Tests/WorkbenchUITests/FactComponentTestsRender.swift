import AppKit
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The fact components drawn to PNG files for a person to look at, in light and dark at two zooms. The folder comes
/// from `FACT_SHOTS_DIR`, else the temporary folder.
@Suite struct FactComponentTestsRender {
    private struct Labelled<Content: View>: View {
        let label: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label).text(.caption)
                content
            }
        }
    }

    private static let offered: [FactAction] = [.done, .snooze(days: 1), .notRelevant, .wrong]
    private static let long = String(
        repeating: "kal subah Meera ko signed offer letter aur bank details bhej dena, warna payment ruk jayegi. ",
        count: 3)

    private static func card(
        _ row: FactRow, selected: Bool = false, hovered: Bool = false, confirming: FactAction? = nil,
        offered: [FactAction] = offered
    ) -> some View {
        FactCard(
            row: row, offered: offered, isSelected: selected, isHovered: hovered, confirming: confirming,
            now: FactFixture.now, hover: { _ in }, open: {}, act: { _ in })
    }

    private static let asha = FactFixture.row(
        1, chat: "Founders group", due: 0, quote: "login API aaj raat tak bhej dunga")
    private static let meera = FactFixture.row(
        5, person: "Meera", chat: "Hiring", due: -2, quote: "I will share the offer letter by Friday")

    private struct CardStates: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Space.m) {
                Labelled(label: "Rest") { FactComponentTestsRender.card(asha) }
                Labelled(label: "Hover") { FactComponentTestsRender.card(asha, hovered: true) }
                Labelled(label: "Selected") { FactComponentTestsRender.card(asha, selected: true) }
                Labelled(label: "Random check, hover") {
                    FactComponentTestsRender.card(
                        FactFixture.row(
                            4, person: "Raj", chat: "Raj", askedWith: 0.2, quote: "payment kal tak kar dunga"),
                        hovered: true, offered: [.right, .wrong])
                }
                Labelled(label: "Late") { FactComponentTestsRender.card(meera) }
                Labelled(label: "Long quote") {
                    FactComponentTestsRender.card(FactFixture.row(6, chat: "Founders group", due: 3, quote: long))
                }
                Labelled(label: "Devanagari and emoji") {
                    FactComponentTestsRender.card(
                        FactFixture.row(10, person: "Priya", chat: "Team", quote: "कल सुबह तक भेज दूँगी 🙏🏽"))
                }
                Labelled(label: "No person") {
                    FactComponentTestsRender.card(
                        FactFixture.row(7, person: "", due: 1, quote: "pay the vendor in USD"))
                }
                Labelled(label: "No quote, no chat name, no project") {
                    FactComponentTestsRender.card(
                        FactFixture.row(11, title: "Send the signed offer letter", project: "", due: 1, quote: ""))
                }
                Labelled(label: "Confirming done") { FactComponentTestsRender.card(asha, confirming: .done) }
                Labelled(label: "Confirming wrong") { FactComponentTestsRender.card(asha, confirming: .wrong) }
            }
        }
    }

    private struct MarkBars: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Space.m) {
                Labelled(label: "Open fact") {
                    MarkBar(actions: FactComponentTestsRender.offered, act: { _ in })
                }
                Labelled(label: "Random check") { MarkBar(actions: [.right, .wrong], act: { _ in }) }
                Labelled(label: "Machine page") { MarkBar(actions: [.done, .wrong], act: { _ in }) }
            }
        }
    }

    private func draw(_ name: String, mode: String, zoom: Double, view: some View) throws {
        let framed = view.padding(Space.l).frame(width: 720, alignment: .topLeading)
            .zoomed(Zoom(zoom)).background(.pageFill)
        let png = try renderedPNG(of: framed, mode: mode)
        let folder =
            ProcessInfo.processInfo.environment["FACT_SHOTS_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appending(path: "\(name)-\(mode)-\(zoom).png"))
        #expect(png.count > 8_000)
    }

    @Test(arguments: ["light", "dark"], [1.0, 1.5])
    func everyFactPartIsDrawn(mode: String, zoom: Double) throws {
        try draw("fact-card", mode: mode, zoom: zoom, view: CardStates())
        try draw("fact-markbar", mode: mode, zoom: zoom, view: MarkBars())
    }
}
