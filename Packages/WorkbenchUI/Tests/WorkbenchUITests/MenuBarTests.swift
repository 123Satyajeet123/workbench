import AppKit
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct MenuBarNeedsTests {
    private func item(_ id: Int64?, asked: Double? = nil, state: Mark = .proposed) -> Item {
        Item(
            id: id, task: "team", day: WorkDay(containing: Date(timeIntervalSince1970: 1_790_000_000)), scope: "",
            source: .typed, citeFirst: 1, citeLast: 1, start: .now, end: .now, fields: [:], quote: "", state: state,
            run: nil, askedWith: asked)
    }

    private func titled(_ items: Item...) -> [TitledItem] { items.map { ($0, "Fact \($0.id ?? 0)") } }

    @Test func theCountIsTodaysNeedsPlusRandomPicksNoMarkHasAnswered() {
        let needs = MenuBarNeeds(
            needs: titled(item(1), item(2)), randomPicks: titled(item(3, asked: 0.2), item(4, asked: 0.5)))
        #expect(needs.count == 4)
    }

    @Test func aMarkedPickAndAnItemTheAppDidNotPickAreNotCounted() {
        let needs = MenuBarNeeds(
            needs: [],
            randomPicks: titled(
                item(1, asked: 0.2, state: .confirmed), item(2, asked: 0.2, state: .rejected), item(3),
                item(4, asked: 0.3)
            ))
        #expect(needs.count == 1 && needs.top.map(\.id) == [4])
    }

    @Test func anItemInBothListsCountsOnce() {
        let both = item(7, asked: 0.4)
        let needs = MenuBarNeeds(needs: titled(both, item(8)), randomPicks: titled(both))
        #expect(needs.count == 2 && needs.top.map(\.id) == [7, 8])
    }

    @Test func theMenuListsTheTopThreeNeedsFirstAndTheCountStaysWhole() {
        let needs = MenuBarNeeds(
            needs: titled(item(1), item(2)), randomPicks: titled(item(3, asked: 0.1), item(4, asked: 0.1)))
        #expect(needs.top.map(\.id) == [1, 2, 3])
        #expect(needs.count == 4)
        #expect(MenuBarNeeds(needs: titled(item(1)), randomPicks: []).top.count == 1)
    }

    @Test func nothingWaitingGivesZeroAndNoLines() {
        let needs = MenuBarNeeds(needs: [], randomPicks: [])
        #expect(needs.count == 0 && needs.top.isEmpty)
    }

    @Test func aLongTitleIsCutSoTheMenuStaysNarrow() {
        let long = String(repeating: "word ", count: 30)
        let cut = MenuBarNeeds(needs: [(item(1), long)], randomPicks: []).top[0].title
        #expect(cut.count == MenuBarNeeds.titleLimit && cut.hasSuffix("…"))
        let fits = String(repeating: "a", count: MenuBarNeeds.titleLimit)
        #expect(MenuBarNeeds(needs: [(item(1), fits)], randomPicks: []).top[0].title == fits)
    }

    @Test func aTitleThatIsEmptyGetsPlainWordsAndAnItemWithoutAnIdIsLeftOut() {
        let needs = MenuBarNeeds(needs: [(item(1), ""), (item(nil), "Lost")], randomPicks: [])
        #expect(needs.top == [MenuNeed(id: 1, title: MenuBarNeeds.untitled)] && needs.count == 1)
    }
}

@Suite struct MenuBarStateTests {
    @Test func theIconShowsARecordingBeforeWhatNeedsThePersonBeforeCapture() {
        #expect(MenuBarGlyph(isRecording: true, needs: 3, status: .capturing) == .recording)
        #expect(MenuBarGlyph(isRecording: false, needs: 3, status: .capturing) == .needsYou)
        #expect(MenuBarGlyph(isRecording: false, needs: 1, status: .off) == .needsYou)
        #expect(MenuBarGlyph(isRecording: false, needs: 0, status: .capturing) == .capturing)
        #expect(MenuBarGlyph(isRecording: false, needs: 0, status: .paused) == .off)
        #expect(MenuBarGlyph(isRecording: false, needs: 0, status: .needsPermission) == .off)
    }

    @Test func theStatusLineNamesWhatReads() {
        #expect(MenuBarStatus.line(capture: .capturing, reading: ["Pip"]) == "Capture on · Pip reading")
        #expect(
            MenuBarStatus.line(capture: .capturing, reading: ["Pip", "Atlas"]) == "Capture on · 2 machines reading")
        #expect(MenuBarStatus.line(capture: .paused, reading: []) == "Capture paused")
    }

    @MainActor @Test func theThreeIconsLookDifferentAndStayTemplates() throws {
        let images = [MenuBarGlyph.off, .capturing, .needsYou].map(MenuBarIcon.glyph)
        #expect(images.allSatisfy { $0.isTemplate && $0.size == MenuBarIcon.glyphSize })
        let bytes = try images.map { try #require($0.tiffRepresentation) }
        #expect(Set(bytes).count == 3)
    }

    @Test func aMenuChoiceAsksTodayForThatFact() {
        let navigation = Navigation()
        navigation.requested = .crew
        navigation.show(fact: 42)
        #expect(navigation.requested == .day && navigation.requestedFact == 42)
    }
}

/// The island, the three menu bar icons with the count, and the menu's lines, drawn to PNGs on a light and a dark
/// menu bar for a person to look at. The folder comes from `VC_PREVIEW_DIR`, else the temporary folder.
@MainActor @Suite struct AmbientRenderTests {
    private struct Bar<Content: View>: View {
        let scheme: ColorScheme
        @ViewBuilder let content: Content

        var body: some View {
            content.padding(.horizontal, 24).frame(height: 44)
                .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.91))
                .environment(\.colorScheme, scheme)
        }
    }

    private func write(_ view: some View, named name: String, scheme: ColorScheme) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder =
            ProcessInfo.processInfo.environment["VC_PREVIEW_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
        #expect(png.count > 3_000)
    }

    private func island(_ state: IslandState) -> some View {
        IslandView(presenter: IslandPresenter(metrics: .sample, showing: state))
    }

    @Test(arguments: [ColorScheme.light, .dark]) func theIslandIsDrawnRecordingAndReading(scheme: ColorScheme) throws {
        let since = Date().addingTimeInterval(-3_725)
        let bar = { (state: IslandState) in
            Bar(scheme: scheme) { island(state) }.frame(width: IslandMetrics.sample.panelSize.width + 48)
        }
        try write(bar(.recording(since: since)), named: "island-recording", scheme: scheme)
        try write(bar(.reading(names: ["Atlas"], page: .crew)), named: "island-reading", scheme: scheme)
        try write(
            bar(.reading(names: ["Quarterly investor update"], page: .crew)), named: "island-reading-long",
            scheme: scheme)
        try write(bar(.reading(names: ["Atlas", "Pip"], page: .crew)), named: "island-reading-two", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.light, .dark]) func theThreeMenuBarIconsAreDrawnWithTheCount(scheme: ColorScheme)
        throws
    {
        let icon = { (glyph: MenuBarGlyph, count: Int?) in
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.glyph(glyph))
                if let count { Text("\(count)").monospacedDigit() }
            }
        }
        let row = HStack(spacing: 40) {
            icon(.off, nil)
            icon(.capturing, nil)
            icon(.needsYou, 4)
            icon(.recording, 4)
        }
        try write(Bar(scheme: scheme) { row }, named: "menubar-icons", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.light, .dark]) func theMenuLinesAreDrawn(scheme: ColorScheme) throws {
        let needs = ["Send Raj the signing key", "Pick USD or INR for the invoice", "Meera's PR waits on you"]
        let menu = VStack(alignment: .leading, spacing: 6) {
            Text(MenuBarStatus.line(capture: .capturing, reading: ["Pip"])).foregroundStyle(.secondary)
            Divider()
            Text("Needs you (5)").foregroundStyle(.secondary)
            ForEach(needs, id: \.self) { Text($0) }
            Divider()
            Text("Open Workbench")
            Divider()
            Text("Record a call")
            Text("Pause for 1 hour")
            Text("Private mode")
            Divider()
            Text("Settings…")
            Text("Quit Workbench")
        }
        .font(.system(size: 13)).padding(14).frame(width: 300, alignment: .leading)
        .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96))
        try write(menu, named: "menubar-menu", scheme: scheme)
    }
}
