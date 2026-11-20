import SwiftUI

/// The one motion of the app: a change settles in 250 ms, ease in and out, and with Reduce Motion on nothing moves.
enum Motion {
    static let duration = 0.25

    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
