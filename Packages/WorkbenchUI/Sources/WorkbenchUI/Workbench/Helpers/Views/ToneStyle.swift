import SwiftUI
import WorkbenchCore

extension HelperSpec.Tone {
    var color: Color {
        switch self {
        case .good: Tone.good.color
        case .attention: Tone.attention.color
        case .bad: Tone.bad.color
        case .neutral: Tone.neutral.color
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.seal.fill"
        case .attention: "exclamationmark.circle.fill"
        case .bad: "exclamationmark.octagon.fill"
        case .neutral: "circle.fill"
        }
    }
}
