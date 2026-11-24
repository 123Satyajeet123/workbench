import AppKit
import SwiftUI

@testable import WorkbenchCore
@testable import WorkbenchUI

public struct RenderFailure: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) { self.description = description }
}

/// Draws a view in an offscreen window at a fixed size, in the light or the dark appearance, and writes it to a PNG.
@MainActor
public func snapshot(_ view: some View, named name: String, dark: Bool, size: CGSize, in folder: URL) async throws
    -> URL
{
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let framed = view.zoomed(Zoom(1)).background(.pageFill).environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: framed)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw RenderFailure("no bitmap for \(name)")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "\(name)-\(dark ? "dark" : "light").png")
    guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 10_000 else {
        throw RenderFailure("\(name) drew blank")
    }
    try png.write(to: file)
    return file
}

/// A machine's page as the app draws it, in an offscreen window.
@MainActor
public func snapshot(
    pageOf model: MachinePageModel, subtitle: String, crew: Crew, models: ModelSettings, named name: String,
    dark: Bool, size: CGSize, in folder: URL
) async throws -> URL {
    let rename = model.renaming { crew.rename(model.helper, to: $0) }
    let page = Page(title: model.name, subtitle: subtitle, rename: rename) { MachinePageView(model: model) }
        .environment(crew).environment(models)
    return try await snapshot(page, named: name, dark: dark, size: size, in: folder)
}
