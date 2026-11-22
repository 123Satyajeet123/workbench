// Source: ports p2panda p2panda-core/src/operation/validation.rs:81-108 (validate_backlink: the next sequence names the
// hash of the one before). Built: every position with two signed events is fork evidence (p2panda drops the second,
// p2panda-stream/src/ingest/operation.rs:174-190), and the view is updated on insert, stream by stream.

/// Every correctly signed event received, and the view they give. The view depends only on which events were
/// inserted, never on their order or on copies. An insert updates only its own stream, from its position on.
public struct Ledger: Sendable {
    private let keys: [DeviceID: DevicePublicKey]
    private var positions: [StreamID: [UInt64: [EventID: Event]]] = [:]
    private var refusedAtNext: [StreamID: EventID] = [:]
    public private(set) var view = LedgerView()

    /// A ledger that accepts events signed by `keys`, such as the devices of the roster.
    public init(keys: some Sequence<DevicePublicKey>) {
        self.keys = Dictionary(keys.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The last accepted event of `stream`: the sequence and id the stream's next event must name.
    public func head(of stream: StreamID) -> StreamHead? {
        view.accepted[stream]?.last.map { StreamHead(sequence: $0.header.sequence, id: $0.id) }
    }

    /// Stores `event` if its stream's device signed it. Of two signatures over one header, the smaller is kept, so
    /// every ledger keeps the same bytes.
    public mutating func insert(_ event: Event) throws(EventError) {
        let header = event.header
        guard let key = keys[header.stream.device] else { throw .unknownDevice }
        guard event.isSigned(by: key) else { throw .badSignature }
        if let held = positions[header.stream]?[header.sequence]?[event.id] {
            if event.signature.lexicographicallyPrecedes(held.signature) { replaceCopy(event) }
            return
        }
        positions[header.stream, default: [:]][header.sequence, default: [:]][event.id] = event
        recordForkIfAny(at: header.position)
        let next = nextSequence(of: header.stream)
        if header.sequence > next {
            view.waiting.insert(event.id)
            return
        }
        if header.sequence < next { truncate(header.stream, to: header.sequence, from: next) }
        advance(header.stream)
    }

    private func nextSequence(of stream: StreamID) -> UInt64 { UInt64(view.accepted[stream]?.count ?? 0) + 1 }

    private func events(at position: StreamPosition) -> [Event] {
        (positions[position.stream]?[position.sequence]?.values).map { $0.sorted { $0.id < $1.id } } ?? []
    }

    private mutating func recordForkIfAny(at position: StreamPosition) {
        let twins = events(at: position)
        if twins.count > 1 { view.forkEvidence[position] = Fork(position: position, events: twins) }
    }

    /// A second event arrived at an accepted position: the chain stops before it, and what followed waits.
    private mutating func truncate(_ stream: StreamID, to sequence: UInt64, from next: UInt64) {
        view.accepted[stream]?.removeLast(Int(next - sequence))
        if view.accepted[stream]?.isEmpty == true { view.accepted[stream] = nil }
        clearRefusal(of: stream)
        for later in (sequence + 1)...next {
            if let ids = positions[stream]?[later]?.keys { view.waiting.formUnion(ids) }
        }
    }

    /// Accepts events from the stream's next position while each is the only one there and links to the one before.
    private mutating func advance(_ stream: StreamID) {
        clearRefusal(of: stream)
        while let candidates = positions[stream]?[nextSequence(of: stream)] {
            view.waiting.subtract(candidates.keys)
            guard candidates.count == 1, let event = candidates.values.first else { return }
            if let previous = view.accepted[stream]?.last, let refusal = Self.refusal(of: event, after: previous) {
                refusedAtNext[stream] = event.id
                view.rejected[event.id] = refusal
                return
            }
            view.accepted[stream, default: []].append(event)
        }
    }

    private mutating func clearRefusal(of stream: StreamID) {
        guard let refused = refusedAtNext.removeValue(forKey: stream) else { return }
        view.rejected[refused] = nil
    }

    private mutating func replaceCopy(_ event: Event) {
        let header = event.header
        positions[header.stream, default: [:]][header.sequence, default: [:]][event.id] = event
        recordForkIfAny(at: header.position)
        let index = Int(header.sequence) - 1
        if let chain = view.accepted[header.stream], chain.indices.contains(index), chain[index].id == event.id {
            view.accepted[header.stream]?[index] = event
        }
    }

    private static func refusal(of event: Event, after previous: Event) -> Rejection? {
        if event.header.backlink != previous.id { return .backlinkMismatch }
        if event.header.hlc <= previous.header.hlc { return .hlcNotRising }
        return nil
    }
}

/// The last accepted position of a stream.
public struct StreamHead: Hashable, Sendable {
    public let sequence: UInt64
    public let id: EventID
}

/// Why an event that is the only one at its stream's next position was refused.
public enum Rejection: Hashable, Sendable {
    case backlinkMismatch
    case hlcNotRising
}

/// Two or more correctly signed events at one position: proof that the device signed both.
public struct Fork: Hashable, Sendable {
    public let position: StreamPosition
    /// Sorted by id.
    public let events: [Event]

    public init(position: StreamPosition, events: [Event]) {
        self.position = position
        self.events = events
    }
}

/// What a set of events shows. Per stream: the accepted chain from sequence 1, the refused event that stopped it if
/// any, and the events past its next position, which wait. Across all positions: every fork.
public struct LedgerView: Equatable, Sendable {
    public internal(set) var accepted: [StreamID: [Event]] = [:]
    public internal(set) var rejected: [EventID: Rejection] = [:]
    public internal(set) var waiting: Set<EventID> = []
    var forkEvidence: [StreamPosition: Fork] = [:]

    /// Every position that holds two or more signed events, in position order.
    public var forks: [Fork] { forkEvidence.values.sorted { $0.position < $1.position } }
}
