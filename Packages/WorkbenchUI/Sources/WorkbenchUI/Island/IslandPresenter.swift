import Observation
import SwiftUI

/// What the island draws, and the moves between two states. It owns the metrics, so a screen change updates them in
/// place and the view stays.
@Observable
final class IslandPresenter {
    private(set) var metrics: IslandMetrics
    private(set) var content = IslandState.idle
    private(set) var isOpen = false
    private(set) var isDrawn = false
    private(set) var isContentVisible = false
    private(set) var isExpanded = false
    private(set) var isDetailVisible = false
    /// The panel has room for the expanded shape. It grows before the shape expands, and shrinks after it collapsed.
    private(set) var isTall = false
    @ObservationIgnored private var target = IslandState.idle
    @ObservationIgnored private var isHovered = false
    @ObservationIgnored private var isAnnouncing = false
    @ObservationIgnored private var moves: Task<Void, Never>?

    init(metrics: IslandMetrics) {
        self.metrics = metrics
    }

    /// A presenter that already shows `state`, expanded when `expanded`, with nothing moving.
    convenience init(metrics: IslandMetrics, showing state: IslandState, expanded: Bool = false) {
        self.init(metrics: metrics)
        target = state
        content = state
        isOpen = state != .idle
        isDrawn = isOpen
        isContentVisible = isOpen
        isExpanded = isOpen && expanded
        isDetailVisible = isExpanded
        isTall = isExpanded
    }

    func place(_ metrics: IslandMetrics) {
        if self.metrics != metrics { self.metrics = metrics }
    }

    func show(_ target: IslandState, reduceMotion: Bool) {
        self.target = target
        move(reduceMotion: reduceMotion)
    }

    func hover(_ isHovered: Bool, reduceMotion: Bool) {
        guard self.isHovered != isHovered else { return }
        self.isHovered = isHovered
        move(reduceMotion: reduceMotion)
    }

    /// Expands the island under the notch for `duration` with no hover, so a question is seen. It ends early when the
    /// calling task is cancelled.
    func announce(for duration: Duration, reduceMotion: Bool) async {
        isAnnouncing = true
        move(reduceMotion: reduceMotion)
        try? await Task.sleep(for: duration)
        isAnnouncing = false
        move(reduceMotion: reduceMotion)
    }

    private func move(reduceMotion: Bool) {
        moves?.cancel()
        let shown = IslandShown(
            content: content, isOpen: isOpen, isContentVisible: isContentVisible, isExpanded: isExpanded,
            isDetailVisible: isDetailVisible)
        let steps = IslandSequence.steps(
            from: shown, to: target, isHovered: isHovered || isAnnouncing, reduceMotion: reduceMotion)
        moves = Task {
            for step in steps {
                guard !Task.isCancelled else { return }
                await perform(step, reduceMotion: reduceMotion)
            }
        }
    }

    private func perform(_ step: IslandStep, reduceMotion: Bool) async {
        let reveal = Motion.reveal(reduceMotion: reduceMotion)
        switch step {
        case .setContent(let state): content = state
        case .openShape:
            isDrawn = true
            withAnimation(Motion.island(reduceMotion: reduceMotion)) { isOpen = true }
        case .closeShape:
            reshape(reduceMotion: reduceMotion) {
                self.isOpen = false
            } arrived: {
                if !self.isOpen { self.isDrawn = false }
            }
        case .expandShape:
            isTall = true
            withAnimation(Motion.island(reduceMotion: reduceMotion)) { isExpanded = true }
        case .collapseShape:
            reshape(reduceMotion: reduceMotion) {
                self.isExpanded = false
            } arrived: {
                if !self.isExpanded { self.isTall = false }
            }
        case .showContent: withAnimation(reveal) { isContentVisible = true }
        case .hideContent: withAnimation(reveal) { isContentVisible = false }
        case .showDetail: withAnimation(reveal) { isDetailVisible = true }
        case .hideDetail: withAnimation(reveal) { isDetailVisible = false }
        case .wait(let duration): try? await Task.sleep(for: duration)
        }
    }

    /// Runs `change` with the island's motion, and `arrived` once the shape is where `change` sent it. The shape is
    /// drawn, and the panel keeps its room, until then.
    private func reshape(reduceMotion: Bool, _ change: () -> Void, arrived: @escaping () -> Void) {
        guard let animation = Motion.island(reduceMotion: reduceMotion) else {
            change()
            arrived()
            return
        }
        withAnimation(animation, completionCriteria: .logicallyComplete, change, completion: arrived)
    }
}
