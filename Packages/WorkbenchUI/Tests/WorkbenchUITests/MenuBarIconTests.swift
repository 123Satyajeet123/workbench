import AppKit
import Testing

@testable import WorkbenchUI

@MainActor struct MenuBarIconTests {
    @Test func theGlyphIsATemplateTheMenuBarTintsAndDimsWhenNotCapturing() throws {
        let full = MenuBarIcon.glyph(dimmed: false)
        let dim = MenuBarIcon.glyph(dimmed: true)
        #expect(full.isTemplate && dim.isTemplate)
        #expect(full.size == MenuBarIcon.glyphSize)
        let fullAlpha = try #require(Self.alpha(of: full, at: CGPoint(x: 0.5, y: 0.7)))
        let dimAlpha = try #require(Self.alpha(of: dim, at: CGPoint(x: 0.5, y: 0.7)))
        #expect(fullAlpha > 0.9 && dimAlpha < fullAlpha)
    }

    private static func alpha(of image: NSImage, at unit: CGPoint) -> CGFloat? {
        guard let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return nil }
        let x = Int(unit.x * CGFloat(rep.pixelsWide))
        let y = Int(unit.y * CGFloat(rep.pixelsHigh))
        return rep.colorAt(x: x, y: y)?.alphaComponent
    }
}
