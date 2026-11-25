public func lanePoints(_ length: Int) -> Int {
    switch length {
    case 1: 1
    case 2: 2
    case 3: 4
    case 4: 7
    case 5: 10
    default: 15
    }
}

public func beaconCost(_ lane: Lane, hazards: Bool) -> Int {
    hazards && lane.hazard == .gravityWell ? lane.length + 1 : lane.length
}

/// Deduped, sorted by core count ascending, then color raw value.
/// With hazards on, a Spectrum lane needs distinct colors and a Gravity Well lane pays one card fewer.
public func paymentOptions(for lane: Lane, hand: Hand, hazards: Bool) -> [Payment] {
    var options: [(cores: Int, key: String, payment: Payment)] = []
    if hazards && lane.hazard == .spectrum {
        let held = ResourceColor.allCases.filter { hand.count(.resource($0)) > 0 }
        for cores in 0...lane.length where hand.count(.core) >= cores {
            for subset in subsets(of: held, size: lane.length - cores) {
                var counts: [Card: Int] = [.core: cores]
                for c in subset { counts[.resource(c)] = 1 }
                options.append((cores, subset.map(\.rawValue).joined(separator: ","), Payment(counts)))
            }
        }
    } else {
        let colors: [ResourceColor]
        switch lane.color {
        case let .color(c): colors = [c]
        case .open: colors = ResourceColor.allCases
        }
        let length = hazards && lane.hazard == .gravityWell ? lane.length - 1 : lane.length
        for color in colors {
            for cores in 0...length {
                let plain = length - cores
                guard hand.count(.core) >= cores, hand.count(.resource(color)) >= plain else { continue }
                options.append((cores, color.rawValue, Payment([.resource(color): plain, .core: cores])))
            }
        }
    }
    var seen = Set<Payment>()
    return options
        .sorted { ($0.cores, $0.key) < ($1.cores, $1.key) }
        .compactMap { seen.insert($0.payment).inserted ? $0.payment : nil }
}

private func subsets<T>(of items: [T], size: Int) -> [[T]] {
    if size == 0 { return [[]] }
    guard items.count >= size else { return [] }
    let head = items[0], rest = Array(items.dropFirst())
    return subsets(of: rest, size: size - 1).map { [head] + $0 } + subsets(of: rest, size: size)
}

/// A lane is closed once its twin is claimed and there are 3 or fewer Houses.
public func isClosed(_ lane: Lane, in s: GameState) -> Bool {
    isClosed(lane, laneOwner: s.laneOwner, playerCount: s.players.count)
}

/// `isClosed(_:in:)` from public values.
public func isClosed(_ lane: Lane, laneOwner: [Int: Int], playerCount: Int) -> Bool {
    guard let twin = lane.twinID else { return false }
    return laneOwner[twin] != nil && playerCount <= 3
}

/// Shared claim guard, in validation order: taken, closed, own twin, beacons.
/// nil means the lane is claimable by `seat`, who has `beacons` left.
public func claimBlocker(_ lane: Lane, seat: Int, laneOwner: [Int: Int], playerCount: Int,
                         beacons: Int, hazards: Bool) -> RuleError? {
    if laneOwner[lane.id] != nil { return .laneTaken }
    if isClosed(lane, laneOwner: laneOwner, playerCount: playerCount) { return .laneClosed }
    if let twin = lane.twinID, laneOwner[twin] == seat { return .ownsTwin }
    if beacons < beaconCost(lane, hazards: hazards) { return .notEnoughBeacons }
    return nil
}
