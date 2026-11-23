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
    @ObservationIgnored private var moves: Task<Void, Never>?

    init(metrics: IslandMetrics) {
        self.metrics = metrics
    }

    /// A presenter that already shows `state`, with nothing moving.
    convenience init(metrics: IslandMetrics, showing state: IslandState) {
        self.init(metrics: metrics)
        content = state
        isOpen = state != .idle
        isDrawn = isOpen
        isContentVisible = isOpen
    }

    func place(_ metrics: IslandMetrics) {
        if self.metrics != metrics { self.metrics = metrics }
    }

    func show(_ target: IslandState, reduceMotion: Bool) {
        moves?.cancel()
        let shown = IslandShown(content: content, isOpen: isOpen, isContentVisible: isContentVisible)
        let steps = IslandSequence.steps(from: shown, to: target, reduceMotion: reduceMotion)
        moves = Task {
            for step in steps {
                guard !Task.isCancelled else { return }
                await perform(step, reduceMotion: reduceMotion)
            }
        }
    }

    private func perform(_ step: IslandStep, reduceMotion: Bool) async {
        switch step {
        case .setContent(let state): content = state
        case .openShape:
            isDrawn = true
            withAnimation(Motion.island(reduceMotion: reduceMotion)) { isOpen = true }
        case .closeShape: closeShape(reduceMotion: reduceMotion)
        case .showContent: withAnimation(Motion.reveal(reduceMotion: reduceMotion)) { isContentVisible = true }
        case .hideContent: withAnimation(Motion.reveal(reduceMotion: reduceMotion)) { isContentVisible = false }
        case .wait(let duration): try? await Task.sleep(for: duration)
        }
    }

    /// The shape is drawn until it is back at the notch's width, so it never fades out wider than the notch.
    private func closeShape(reduceMotion: Bool) {
        guard let animation = Motion.island(reduceMotion: reduceMotion) else {
            isOpen = false
            isDrawn = false
            return
        }
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            isOpen = false
        } completion: {
            if !self.isOpen { self.isDrawn = false }
        }
    }
}
