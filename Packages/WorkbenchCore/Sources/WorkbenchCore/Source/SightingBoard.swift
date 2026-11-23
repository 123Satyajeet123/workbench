import Foundation
import Synchronization

/// The containers a push source's page showed while the person had the chooser open, kept in memory only. A page sends
/// a sighting only when the app says it asks (`isOpen`); the app opens that window when the person asks for the list and
/// closes it when the chooser goes away. Nothing here reaches the store: choosing a container is the person's act, and
/// it is the allow-list that records it.
public final class SightingBoard: ContainerSource, Sendable {
    public let descriptor: SourceDescriptor

    private struct State {
        var isOpen = false
        /// Newest last.
        var sightings: [ContainerSighting] = []
        /// Containers a reading refused, by id, with the words that tell the person what to do.
        var waiting: [String: String] = [:]
        var onChange: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    public init(descriptor: SourceDescriptor) { self.descriptor = descriptor }

    public var isOpen: Bool { state.withLock { $0.isOpen } }

    public func open() { state.withLock { $0.isOpen = true } }

    /// Closing forgets every sighting: they were the answer to one question.
    public func close() {
        let notify = state.withLock { state -> (@Sendable () -> Void)? in
            state.isOpen = false
            state.sightings = []
            return state.onChange
        }
        notify?()
    }

    /// Called after a sighting is kept or forgotten, from any thread.
    public func onChange(_ handler: @escaping @Sendable () -> Void) { state.withLock { $0.onChange = handler } }

    /// Keeps the newest sighting of its container. Returns false, and keeps nothing, while the window is closed.
    @discardableResult
    public func record(_ sighting: ContainerSighting) -> Bool {
        let result = state.withLock { state -> (kept: Bool, notify: (@Sendable () -> Void)?) in
            guard state.isOpen else { return (false, nil) }
            state.sightings.removeAll { $0.container.id == sighting.container.id }
            state.sightings.append(sighting)
            return (true, state.onChange)
        }
        result.notify?()
        return result.kept
    }

    /// Drops what the board holds of one container: its sighting, its members and its note.
    public func forget(_ containerID: String) {
        let notify = state.withLock { state -> (@Sendable () -> Void)? in
            state.sightings.removeAll { $0.container.id == containerID }
            state.waiting[containerID] = nil
            return state.onChange
        }
        notify?()
    }

    public func sightings(policy: CapturePolicy, now: Date) -> [ContainerSighting] {
        guard policy.isEnabled(descriptor.consent) else { return [] }
        return state.withLock { Array($0.sightings.reversed()) }
    }

    /// A reading of this container was refused for lack of a member list; `words` say what the person can do.
    public func wait(on containerID: String, words: String) { state.withLock { $0.waiting[containerID] = words } }

    public func stopWaiting(on containerID: String) { state.withLock { $0.waiting[containerID] = nil } }

    /// Why a chosen container is not being read, in words for the person; nil when nothing waits.
    public func waiting(on containerID: String) -> String? { state.withLock { $0.waiting[containerID] } }
}
