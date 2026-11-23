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
    private static let long = String(repeating: "Ask Meera for the signed offer letter and the bank details ", count: 4)

    private static func card(
        _ row: FactRow, selected: Bool = false, hovered: Bool = false, confirming: FactAction? = nil,
        offered: [FactAction] = offered
    ) -> some View {
        FactCard(
            row: row, offered: offered, isSelected: selected, isHovered: hovered, confirming: confirming,
            now: FactFixture.now, hover: { _ in }, open: {}, act: { _ in })
    }

    private struct CardStates: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Space.m) {
                Labelled(label: "Rest") {
                    FactComponentTestsRender.card(FactFixture.row(1, reason: .asksYou, due: 0))
                }
                Labelled(label: "Hover") {
                    FactComponentTestsRender.card(FactFixture.row(2, reason: .asksYou, due: 0), hovered: true)
                }
                Labelled(label: "Selected") {
                    FactComponentTestsRender.card(FactFixture.row(3, reason: .asksYou, due: 0), selected: true)
                }
                Labelled(label: "Audit pick") {
                    FactComponentTestsRender.card(
                        FactFixture.row(4, title: "Share the offer letter draft", person: "Meera", askedWith: 0.2))
                }
                Labelled(label: "Overdue") {
                    FactComponentTestsRender.card(
                        FactFixture.row(
                            5, title: "Share the offer letter draft", reason: .overdue, person: "Meera", due: -2))
                }
                Labelled(label: "Long title") {
                    FactComponentTestsRender.card(FactFixture.row(6, title: long, reason: .asksYou, due: 3))
                }
                Labelled(label: "No person") {
                    FactComponentTestsRender.card(FactFixture.row(7, person: "", due: 1))
                }
                Labelled(label: "Confirming done") {
                    FactComponentTestsRender.card(FactFixture.row(8), confirming: .done)
                }
                Labelled(label: "Confirming wrong") {
                    FactComponentTestsRender.card(FactFixture.row(9), confirming: .wrong)
                }
            }
        }
    }

    private struct MarkBars: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Space.m) {
                Labelled(label: "Open fact") {
                    MarkBar(actions: FactComponentTestsRender.offered, isChoosing: .constant(false), act: { _ in })
                }
                Labelled(label: "Audit pick or other item") {
                    MarkBar(actions: [.right, .wrong], isChoosing: .constant(false), act: { _ in })
                }
                Labelled(label: "Machine page") {
                    MarkBar(actions: [.done, .wrong], isChoosing: .constant(false), act: { _ in })
                }
            }
        }
    }

    private struct Lists: View {
        let rows = [
            FactFixture.row(1, title: "Blocked on the signing key", reason: .asksYou, due: 0),
            FactFixture.row(2, title: "Share the offer letter draft", reason: .overdue, person: "Meera", due: -2),
            FactFixture.row(3, title: "Pay the vendor in USD or INR?", reason: .asksYou, person: "Raj"),
            FactFixture.row(4, title: "Call the designer shortlist", person: "Meera", due: 3),
            FactFixture.row(5, title: "Review the payments webhook", person: "Raj", askedWith: 0.2),
        ]

        private func list(_ rows: [FactRow], limit: Int = 8) -> some View {
            let selection = FactSelection()
            selection.selected = 2
            return FactList(
                rows: rows, acting: FakeActing(), surface: .today, selection: selection, toast: ToastCenter(),
                limit: limit, now: FactFixture.now,
                empty: { Text("Nothing needs you.").text(.meta).padding(Space.m) },
                closing: { Text("That's all for today.").text(.meta).padding(Space.m) })
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Space.l) {
                Labelled(label: "Five facts, the second selected") { list(rows) }
                Labelled(label: "Capped at three") { list(rows, limit: 3) }
                Labelled(label: "Empty") { list([]) }
            }
        }
    }

    /// Draws through AppKit, which also draws menus and other native controls that `ImageRenderer` leaves blank.
    private func draw(_ name: String, mode: String, zoom: Double, view: some View) throws {
        let framed = view.padding(Space.l).frame(width: 720, alignment: .topLeading)
            .zoomed(Zoom(zoom)).background(.pageFill)
        let host = NSHostingView(rootView: framed)
        let appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.appearance = appearance
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: [], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * 2, pixelsHigh: Int(bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        host.cacheDisplay(in: bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
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
        try draw("fact-list", mode: mode, zoom: zoom, view: Lists())
    }
}
