import SwiftUI
import Testing

@testable import WorkbenchUI

@Suite struct ZoomTests {
    @Test func zoomStepsInAndOutBetweenItsBoundsAndSnapsAStoredValueToAStep() {
        #expect(Zoom().scale == 1)
        #expect(Zoom().zoomedIn.scale == 1.15)
        #expect(Zoom().zoomedOut.scale == 0.85)
        #expect(Zoom(1.75).zoomedIn.scale == 1.75 && !Zoom(1.75).canZoomIn)
        #expect(Zoom(0.85).zoomedOut.scale == 0.85 && !Zoom(0.85).canZoomOut)
        #expect(Zoom(1.2).scale == 1.15)
        #expect(Zoom(9).scale == 1.75)
        #expect(Zoom(0.85).controlSize == .small && Zoom(1.5).controlSize == .large && Zoom().controlSize == .regular)
    }

    @Test func textGrowsWithTheZoomAndEveryScreenFontGoesThroughIt() throws {
        func width(_ scale: Double) -> CGFloat {
            NSHostingView(rootView: Text("Review the login API").zoomed(Zoom(scale)).fixedSize()).fittingSize.width
        }
        #expect(width(1.5) > width(1) * 1.3)
        #expect(width(0.85) < width(1))
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/WorkbenchUI")
            .standardized
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var fixed: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "Zoom.swift"
        {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.firstMatch(of: #/\.font\(\.(?!system\()/#) != nil { fixed.append(file.lastPathComponent) }
        }
        #expect(fixed.isEmpty, "a fixed text style escapes the zoom in \(fixed)")
    }
}
