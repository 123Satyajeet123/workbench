import SwiftUI

/// The motion of the app. Each token is one kind of change. With Reduce Motion on, no token moves anything.
enum Motion {
    static let duration = 0.25

    /// Content changes: a row closes a gap, a note opens.
    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }

    /// Small answers to a person's act: a selection, a mark, a toast.
    static func snap(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)
    }

    /// Controls that appear under the pointer.
    static func reveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    /// The Island changes shape.
    static func island(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }
}
