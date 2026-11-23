import SwiftUI

/// The Go menu: ⌘K, and ⌘1 to ⌘7 for the pages that have a key.
struct ShellCommands: Commands {
    let navigation: Navigation?

    private static let pages: [SidebarSelection] = SidebarSelection.fixed.filter { $0.goKey != nil }

    var body: some Commands {
        CommandMenu("Go") {
            Button("Search…") { navigation?.isPaletteOpen = true }.keyboardShortcut("k")
            Divider()
            ForEach(Self.pages) { page in
                Button(page.title) { navigation?.requested = page }
                    .keyboardShortcut(page.goKey!, modifiers: .command)
            }
        }
    }
}
