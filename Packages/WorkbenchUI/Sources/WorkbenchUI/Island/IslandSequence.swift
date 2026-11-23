import Foundation

/// One move of the island. The shape and its content never move at the same time: the content appears after the shape
/// has mostly opened, and goes before the shape closes.
enum IslandStep: Equatable {
    case setContent(IslandState)
    case openShape, closeShape
    case showContent, hideContent
    case wait(Duration)
}

/// What the island draws now.
struct IslandShown: Equatable {
    var content = IslandState.idle
    var isOpen = false
    var isContentVisible = false
}

enum IslandSequence {
    /// The fade of the content. It equals the `Motion.reveal` curve.
    static let contentFade = Duration.milliseconds(180)
    /// How long the shape opens before the content shows: the spring has covered most of the way.
    static let openLead = Duration.milliseconds(200)

    /// A machine must read this long before the island opens for it, so a quick read draws nothing. A recording never
    /// waits: consent shows at once.
    static let readingDelay = Duration.milliseconds(700)

    /// The moves that take the island from what it shows to `target`. With Reduce Motion nothing animates and
    /// nothing waits for a shape to move.
    static func steps(from shown: IslandShown, to target: IslandState, reduceMotion: Bool) -> [IslandStep] {
        let fade = reduceMotion ? Duration.zero : contentFade
        let hide: [IslandStep] = shown.isContentVisible ? [.hideContent, .wait(fade)] : []
        if target == .idle {
            return hide + (shown.content == .idle ? [] : [.setContent(.idle)]) + (shown.isOpen ? [.closeShape] : [])
        }
        if !shown.isOpen {
            let patience: [IslandStep] = target.isRecording ? [] : [.wait(readingDelay)]
            return patience + [.setContent(target), .openShape, .wait(reduceMotion ? .zero : openLead), .showContent]
        }
        if shown.content != target { return hide + [.setContent(target), .showContent] }
        return shown.isContentVisible ? [] : [.showContent]
    }
}
