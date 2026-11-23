import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor struct SidebarSymbolTests {
    private func strongest(isHot: Bool, in appearance: NSAppearance.Name) throws -> (ink: CGFloat, area: Int) {
        let view = SidebarSymbol(name: "house", isSelected: false, size: 30)
            .environment(\.isSidebarRowHot, isHot)
            .frame(width: 60, height: 60)
            .background(.sidebarFill)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let background = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)?.brightnessComponent)
        var ink: CGFloat = 0
        var area = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let brightness = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent
                else { continue }
                let contrast = abs(brightness - background)
                ink = max(ink, contrast)
                if contrast > 0.3 { area += 1 }
            }
        }
        return (ink, area)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func aHoveredIconTurnsBoldAndFullContrast(appearance: NSAppearance.Name) throws {
        let resting = try strongest(isHot: false, in: appearance)
        let hot = try strongest(isHot: true, in: appearance)
        #expect(hot.ink > 0.8 && hot.ink > resting.ink + 0.2)
        #expect(hot.area > resting.area)
    }
}
