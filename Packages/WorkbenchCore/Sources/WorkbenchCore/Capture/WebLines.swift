import Foundation
import Lines

extension WebPage {
    /// The lines of this page as evidence lines. An item with the site's own id, in a known place, is named by site,
    /// place and id, and is `stable`. Any other item is named by its content (the page address and its text) and is
    /// `ephemeral`: no id is made up. Named lines come first, then the others, each in reading order.
    public func observedLines(readerVersion: String) throws -> [ObservedLine] {
        var named: [ObservedLine] = []
        var unnamed: [String] = []
        for item in items ?? [] {
            if let entity = try entityKey(of: item) {
                let line = Line(entity: entity, text: item.text, readerVersion: readerVersion)
                named.append(ObservedLine(line: line, quality: .stable))
            } else {
                unnamed.append(item.text)
            }
        }
        guard let address = CaptureEngine.address(url) else { return named }
        let byContent = try Line.screen(container: address, texts: unnamed, readerVersion: readerVersion)
        return named + byContent.map { ObservedLine(line: $0, quality: .ephemeral) }
    }

    private func entityKey(of item: Item) throws -> EntityKey? {
        guard let place = container?.value, let id = item.id, !id.isEmpty, let site = CapturePolicy.host(of: url)
        else { return nil }
        return try EntityKey.web(site: site, container: place, itemID: id)
    }
}
