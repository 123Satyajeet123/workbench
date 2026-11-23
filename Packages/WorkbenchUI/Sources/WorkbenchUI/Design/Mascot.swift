import SwiftUI

/// A helper's face: a soft body, two eyes, cheeks, a mouth and one thing it wears. Drawn, so it is sharp at every size.
/// Its mood shows what the helper is doing; the face moves once when the mood changes, never in a loop, and not at all
/// with Reduce Motion on.
struct Mascot: View {
    enum Mood: Hashable {
        case calm, working, asking, trouble
    }

    struct Look: Equatable {
        enum Wear { case crown, antenna, headphones }

        let hue: Double
        let wear: Wear
    }

    let look: Look
    var size: CGFloat = 28
    var mood = Mood.calm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        face
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? .calm : mood) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.12, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.3)
            }
    }

    private var face: some View {
        Canvas { context, canvas in
            let unit = canvas.width
            func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
                CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit)
            }
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            let ink = GraphicsContext.Shading.color(Color(hue: look.hue, saturation: 0.6, brightness: 0.22))

            if look.wear == .headphones {
                var band = Path()
                band.addArc(
                    center: point(0.5, 0.58), radius: 0.42 * unit, startAngle: .degrees(195), endAngle: .degrees(345),
                    clockwise: false)
                context.stroke(band, with: ink, style: StrokeStyle(lineWidth: 0.06 * unit, lineCap: .round))
            }

            let body = Path(roundedRect: rect(0.1, 0.24, 0.8, 0.72), cornerRadius: 0.32 * unit, style: .continuous)
            context.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hue: look.hue, saturation: 0.32, brightness: 1),
                        Color(hue: look.hue, saturation: 0.58, brightness: 0.88),
                    ]), startPoint: point(0.5, 0.24), endPoint: point(0.5, 0.96)))

            for x in [0.37, 0.63] {
                if mood == .working {
                    var lid = Path()
                    lid.move(to: point(x - 0.05, 0.57))
                    lid.addQuadCurve(to: point(x + 0.05, 0.57), control: point(x, 0.62))
                    context.stroke(lid, with: ink, style: StrokeStyle(lineWidth: 0.035 * unit, lineCap: .round))
                } else {
                    context.fill(Path(ellipseIn: rect(x - 0.045, 0.5, 0.09, 0.13)), with: ink)
                    context.fill(Path(ellipseIn: rect(x - 0.01, 0.515, 0.035, 0.035)), with: .color(.white))
                }
            }
            for x in [0.25, 0.75] {
                context.fill(Path(ellipseIn: rect(x - 0.06, 0.67, 0.12, 0.07)), with: .color(.pink.opacity(0.55)))
            }
            var mouth = Path()
            switch mood {
            case .calm, .working:
                mouth.move(to: point(0.45, 0.69))
                mouth.addQuadCurve(to: point(0.55, 0.69), control: point(0.5, 0.76))
            case .asking:
                mouth.addEllipse(in: rect(0.475, 0.68, 0.05, 0.06))
            case .trouble:
                mouth.move(to: point(0.45, 0.74))
                mouth.addQuadCurve(to: point(0.55, 0.74), control: point(0.5, 0.68))
            }
            context.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: 0.03 * unit, lineCap: .round))

            switch look.wear {
            case .crown:
                var crown = Path()
                crown.addLines([
                    point(0.32, 0.27), point(0.3, 0.11), point(0.41, 0.19), point(0.5, 0.06), point(0.59, 0.19),
                    point(0.7, 0.11), point(0.68, 0.27),
                ])
                crown.closeSubpath()
                context.fill(crown, with: .color(Color(hue: 0.12, saturation: 0.75, brightness: 0.98)))
                context.stroke(
                    crown, with: .color(Color(hue: 0.1, saturation: 0.8, brightness: 0.75)),
                    style: StrokeStyle(lineWidth: 0.02 * unit, lineJoin: .round))
            case .antenna:
                var stalk = Path()
                stalk.move(to: point(0.5, 0.25))
                stalk.addQuadCurve(to: point(0.6, 0.09), control: point(0.5, 0.14))
                context.stroke(stalk, with: ink, style: StrokeStyle(lineWidth: 0.035 * unit, lineCap: .round))
                context.fill(
                    Path(ellipseIn: rect(0.54, 0.02, 0.12, 0.12)),
                    with: .color(
                        Color(hue: (look.hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 1))
                )
            case .headphones:
                for x in [0.03, 0.85] {
                    context.fill(
                        Path(roundedRect: rect(x, 0.46, 0.12, 0.24), cornerRadius: 0.05 * unit, style: .continuous),
                        with: ink)
                }
            }

            if let (mark, color) = badge {
                context.fill(Path(ellipseIn: rect(0.7, 0.0, 0.3, 0.3)), with: .color(color))
                context.draw(
                    Text(mark).font(.system(size: 0.24 * unit, weight: .heavy, design: .rounded)).foregroundStyle(
                        .white),
                    at: point(0.85, 0.15))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Mascot {
    fileprivate var badge: (String, Color)? {
        switch mood {
        case .asking: ("?", Tone.attention.color)
        case .trouble: ("!", Tone.bad.color)
        case .calm, .working: nil
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(SidebarSelection.fixed.compactMap(\.look), id: \.hue) { Mascot(look: $0, size: 96) }
    }
    .padding(32)
}
