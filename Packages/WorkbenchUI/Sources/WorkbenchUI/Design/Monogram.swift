import SwiftUI

/// A person as a coloured initial. The colour comes from the name, so it never changes.
struct Monogram: View {
    let name: String
    var size: CGFloat = 28

    private var hue: Double {
        Double(name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    }

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.55, brightness: 0.52), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(["Asha", "Bharat", "Chitra", "Dev"], id: \.self) { Monogram(name: $0, size: 40) }
    }
    .padding()
}
