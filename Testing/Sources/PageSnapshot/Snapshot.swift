import AppKit
import SwiftUI
import WebKit

@testable import WorkbenchCore
@testable import WorkbenchUI

public struct RenderFailure: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) { self.description = description }
}

/// Draws a view in an offscreen window at a fixed size, in the light or the dark appearance, and writes it to a PNG. A
/// web view in the view is drawn from its own snapshot, laid where it stands, once its editor has loaded. `prepare`
/// runs after that and before the picture, to bring the page into the state to show.
@MainActor
public func snapshot(
    _ view: some View, named name: String, dark: Bool, size: CGSize, in folder: URL,
    prepare: () async throws -> Void = {}
) async throws -> URL {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let framed = view.zoomed(Zoom(1)).background(.pageFill).environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: framed)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    let webViews = host.webViews
    for web in webViews { try await web.waitUntilEditorLoaded() }
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    try await prepare()
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw RenderFailure("no bitmap for \(name)")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try await draw(webViews, into: bitmap, of: host)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "\(name)-\(dark ? "dark" : "light").png")
    guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 10_000 else {
        throw RenderFailure("\(name) drew blank")
    }
    try png.write(to: file)
    return file
}

@MainActor
private func draw(_ webViews: [WKWebView], into bitmap: NSBitmapImageRep, of host: NSView) async throws {
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw RenderFailure("no drawing context") }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    for web in webViews {
        let shot = try await web.takeSnapshot(configuration: WKSnapshotConfiguration())
        var rect = host.convert(web.bounds, from: web)
        if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
        shot.draw(in: rect)
    }
}

extension NSView {
    fileprivate var webViews: [WKWebView] {
        (self as? WKWebView).map { [$0] } ?? subviews.flatMap(\.webViews)
    }
}

extension WKWebView {
    fileprivate func waitUntilEditorLoaded() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let loaded = try? await callAsyncJavaScript(
                "return Boolean(window.wbEditor && document.querySelector('.bn-block-outer'))", arguments: [:],
                in: nil, contentWorld: .page)
            if loaded as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RenderFailure("the editor did not load")
    }
}

/// A machine's page as the app draws it, in an offscreen window: the document and nothing around it.
@MainActor
public func snapshot(
    pageOf model: MachinePageModel, crew: Crew, models: ModelSettings, named name: String, dark: Bool, size: CGSize,
    in folder: URL, prepare: () async throws -> Void = {}
) async throws -> URL {
    model.edits = PageEdits(
        rename: { crew.rename(model.helper, to: $0) }, setJob: { crew.setJob(model.helper, to: $0) })
    let page = DocumentPage { MachinePageView(model: model) }.environment(crew).environment(models)
    return try await snapshot(page, named: name, dark: dark, size: size, in: folder, prepare: prepare)
}
