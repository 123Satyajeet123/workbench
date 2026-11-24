import SwiftUI
import WorkbenchCore

/// A gallery template where it is listed before it becomes a machine: its symbol, its name, and what it gives in one
/// line. A machine made from it shows its face instead.
struct GalleryItemLabel: View {
    let template: GalleryTemplate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: template.icon).foregroundStyle(.iconTint).frame(width: Space.l).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(template.name).textStyle(.headline)
                Text(template.detail).textStyle(.callout).foregroundStyle(.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
