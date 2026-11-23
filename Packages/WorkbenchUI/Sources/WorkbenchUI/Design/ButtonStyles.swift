import SwiftUI

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

private struct GhostButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(fill, in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect(cornerRadius: Radius.control))
            .opacity(isEnabled ? 1 : 0.5)
            .pointerStyle(isEnabled ? .link : nil)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return .selectedFill }
        return isHovered ? .hoverFill : .clear
    }
}

private struct PrimaryButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : .supporting)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs * 1.5)
            .background(isEnabled ? Color.accentFill : .selectedFill, in: .rect(cornerRadius: Radius.control))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(.rect(cornerRadius: Radius.control))
            .pointerStyle(isEnabled ? .link : nil)
    }
}
