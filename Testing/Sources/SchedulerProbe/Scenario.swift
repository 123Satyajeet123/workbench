/// Deterministic random numbers, so both arms see the same world.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct Burst {
    let machine: Int
    let count: Int
}

/// Everything that does not depend on the scheduler arm.
struct Scenario {
    static let machines = 30
    static let sources = 5
    static let childCap = 2
    static let activeEnd = 7_200
    static let sleepSeconds = 28_800
    static let wakeAt = activeEnd + sleepSeconds
    static let revokeAt = 3_600
    static let revokedSource = 3
    static let tickSeconds = 60
    static let settleSeconds = 30
    static let seed: UInt64 = 86

    var bursts: [Int: [Burst]] = [:]
    var hints: [Int: [Int]] = [:]
    var catchUp: [Burst] = []

    init() {
        var rng = SplitMix(state: Self.seed)
        for second in 0..<Self.activeEnd {
            for machine in 0..<Self.machines {
                if Int.random(in: 0..<240, using: &rng) == 0 {
                    bursts[second, default: []].append(
                        Burst(machine: machine, count: Int.random(in: 1...8, using: &rng)))
                }
                if Int.random(in: 0..<1_500, using: &rng) == 0 { hints[second, default: []].append(machine) }
            }
        }
        catchUp = (0..<Self.machines).map { Burst(machine: $0, count: Int.random(in: 20...100, using: &rng)) }
    }

    static func source(of machine: Int) -> Int { machine % sources }

    /// Runner delay in seconds, from the machine and its start count only.
    static func delay(machine: Int, startCount: Int) -> Int {
        var rng = SplitMix(state: seed ^ (UInt64(machine) &* 7_919) ^ (UInt64(startCount) &* 104_729))
        return Int.random(in: 40...150, using: &rng)
    }
}

enum Boundary: String, CaseIterable {
    case planned, calling, replied, committed
}

/// Process crashes. Each fires once, at the first matching event at or after its time.
struct CrashPlan {
    private var pending: [(at: Int, boundary: Boundary)]
    private(set) var fired: [Boundary] = []

    static var standard: CrashPlan {
        let early = zip([600, 1_500, 2_400, 3_300], Boundary.allCases)
        let late = zip([60, 300, 600, 900], Boundary.allCases)
        return CrashPlan(
            pending: early.map { (at: $0.0, boundary: $0.1) }
                + late.map { (at: Scenario.wakeAt + $0.0, boundary: $0.1) })
    }

    private init(pending: [(at: Int, boundary: Boundary)]) { self.pending = pending }

    mutating func fires(_ boundary: Boundary, at second: Int) -> Bool {
        guard let index = pending.firstIndex(where: { $0.boundary == boundary && $0.at <= second }) else {
            return false
        }
        pending.remove(at: index)
        fired.append(boundary)
        return true
    }
}
