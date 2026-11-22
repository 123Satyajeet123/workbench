import SwiftUI

enum Motion {
    static let duration = 0.25

    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
