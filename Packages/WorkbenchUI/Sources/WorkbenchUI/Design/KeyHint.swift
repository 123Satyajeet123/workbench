import SwiftUI

/// A key shown next to the action it runs, drawn as a small key cap.
struct KeyHint: View {
    let key: String
    @Environment(\.uiScale) private var scale

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .textStyle(.subheadline, weight: .medium)
            .foregroundStyle(.supporting)
            .padding(.horizontal, Space.xs)
            .frame(minWidth: Self.capHeight * scale, minHeight: Self.capHeight * scale)
            .background(.selectedFill, in: .rect(cornerRadius: Radius.keyCap))
            .overlay(RoundedRectangle(cornerRadius: Radius.keyCap).strokeBorder(.dividerLine))
            .accessibilityLabel("Key \(key)")
    }

    private static let capHeight: CGFloat = 18
}
