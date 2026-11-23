import Foundation

/// One move of the island. The shape and its content never move at the same time: the content appears after the shape
/// has mostly opened, and goes before the shape closes. The detail line under the notch moves the same way when a
/// hover expands the shape.
enum IslandStep: Equatable {
    case setContent(IslandState)
    case openShape, closeShape
    case expandShape, collapseShape
    case showContent, hideContent
    case showDetail, hideDetail
    case wait(Duration)
}

/// What the island draws now.
struct IslandShown: Equatable {
    var content = IslandState.idle
    var isOpen = false
    var isContentVisible = false
    var isExpanded = false
    var isDetailVisible = false
}

enum IslandSequence {
    /// The fade of the content. It equals the `Motion.reveal` curve.
    static let contentFade = Duration.milliseconds(180)
    /// How long the shape opens before the content shows: the spring has covered most of the way.
    static let openLead = Duration.milliseconds(200)

    /// The island must have something to show this long before it opens, so a quick read draws nothing. A recording
    /// never waits: consent shows at once.
    static let readingDelay = Duration.milliseconds(700)

    /// The moves that take the island from what it shows to `target`, expanded under the notch when `isHovered`. With
    /// Reduce Motion nothing animates and nothing waits for a shape to move.
    static func steps(
        from shown: IslandShown, to target: IslandState, isHovered: Bool = false, reduceMotion: Bool
    ) -> [IslandStep] {
        let expands = isHovered && target != .idle
        let changes = shown.content != target
        let fadeOut = hide(shown, keepsContent: !changes, keepsDetail: expands && !changes, reduceMotion: reduceMotion)
        let collapse: [IslandStep] = shown.isExpanded && !expands ? [.collapseShape] : []
        if target == .idle {
            return fadeOut + (changes ? [.setContent(.idle)] : []) + collapse + (shown.isOpen ? [.closeShape] : [])
        }
        let patience: [IslandStep] = shown.isOpen || target.isRecording ? [] : [.wait(readingDelay)]
        let growth: [IslandStep] =
            (shown.isOpen ? [] : [.openShape]) + (expands && !shown.isExpanded ? [.expandShape] : [])
        let lead: [IslandStep] = growth.isEmpty ? [] : [.wait(reduceMotion ? .zero : openLead)]
        let showContent: [IslandStep] = changes || !shown.isContentVisible ? [.showContent] : []
        let showDetail: [IslandStep] = expands && (changes || !shown.isDetailVisible) ? [.showDetail] : []
        return patience + fadeOut + (changes ? [.setContent(target)] : []) + collapse + growth + lead + showContent
            + showDetail
    }

    private static func hide(
        _ shown: IslandShown, keepsContent: Bool, keepsDetail: Bool, reduceMotion: Bool
    ) -> [IslandStep] {
        let detail: [IslandStep] = shown.isDetailVisible && !keepsDetail ? [.hideDetail] : []
        let content: [IslandStep] = shown.isContentVisible && !keepsContent ? [.hideContent] : []
        let fades = detail + content
        return fades.isEmpty ? [] : fades + [.wait(reduceMotion ? .zero : contentFade)]
    }
}
