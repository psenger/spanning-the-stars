/// One Contract a rival may hold, with the share of belief it gets.
public struct ContractGuess: Sendable, Equatable {
    public let contractID: Int
    public let likelihood: Double
}

/// One Contract a rival may be working on, with the route it has now.
public struct BlockTarget: Sendable {
    let rival: Int
    let contract: Contract
    let likelihood: Double
    let route: Route
}

/// Guesses a rival's hidden Contracts from the lanes it has claimed.
public struct OpponentModel: Sendable {
    /// Weight of a Contract the rival has made no progress on.
    static let floor = 0.02
    /// How many of a rival's likeliest Contracts `blockValue` weighs.
    static let guessesPerRival = 5

    private let graph: MapGraph
    private let emptyCost: [Int]   // per Contract id, the route cost on an empty board

    public init(graph: MapGraph) {
        self.graph = graph
        emptyCost = graph.map.contracts.map {
            graph.route(from: $0.a, to: $0.b, seat: 0, laneOwner: [:], playerCount: 2)?.cost ?? 0
        }
    }

    /// Contracts the rival may hold, most likely first; likelihoods sum to 1. Excludes the viewer's own
    /// Contracts. Uses only the view: the rival's lanes, the board and the Contract list.
    public func likelyContracts(of opponent: Int, view: PlayerView) -> [ContractGuess] {
        let weights = graph.map.contracts.filter { !view.contracts.contains($0.id) }.map { c in
            // A route made longer by rival lanes is no progress, and neither is one with no route left.
            let d0 = Double(emptyCost[c.id])
            let progress = cost(c, seat: opponent, laneOwner: view.laneOwner, view: view)
                .map { d0 > 0 ? max(0, (d0 - Double($0)) / d0) : 0 } ?? 0
            return (id: c.id, weight: Self.floor + progress * progress)
        }
        let total = weights.reduce(0) { $0 + $1.weight }
        return weights.map { ContractGuess(contractID: $0.id, likelihood: $0.weight / total) }
            .sorted { ($0.likelihood, $1.contractID) > ($1.likelihood, $0.contractID) }
    }

    /// Standing the viewer expects to deny rivals by claiming this lane: for each rival, the sum over
    /// its 5 likeliest Contracts of likelihood * min(value, rise in that rival's route cost without
    /// the lane), an impossible route counting as the Contract's value. 0 for a lane no rival needs.
    public func blockValue(laneID: Int, view: PlayerView) -> Double {
        let rivals = view.seats.indices.filter { $0 != view.seat }
        return blockValue(laneID: laneID, view: view, targets: blockTargets(of: rivals, view: view))
    }

    /// The Contracts `blockValue` weighs for these rivals, each with the rival's route as the board
    /// stands. Worked out once, they serve every lane of one decision.
    public func blockTargets(of rivals: [Int], view: PlayerView) -> [BlockTarget] {
        rivals.flatMap { rival in
            likelyContracts(of: rival, view: view).prefix(Self.guessesPerRival).compactMap { guess in
                let c = graph.map.contracts[guess.contractID]
                return route(c, seat: rival, laneOwner: view.laneOwner, view: view)
                    .map { BlockTarget(rival: rival, contract: c, likelihood: guess.likelihood, route: $0) }
            }
        }
    }

    /// `blockValue(laneID:view:)` over targets worked out before.
    public func blockValue(laneID: Int, view: PlayerView, targets: [BlockTarget]) -> Double {
        guard view.laneOwner[laneID] == nil else { return 0 }
        var taken = view.laneOwner
        taken[laneID] = view.seat
        let twin = graph.map.lane(laneID).twinID
        var total = 0.0
        for t in targets {
            // A route that uses neither the lane nor its twin stands as it is.
            guard t.route.toClaim.contains(where: { $0 == laneID || $0 == twin }) else { continue }
            let c = t.contract
            let rise = route(c, seat: t.rival, laneOwner: taken, view: view).map { $0.cost - t.route.cost } ?? c.value
            total += t.likelihood * Double(min(c.value, rise))
        }
        return total
    }

    private func route(_ c: Contract, seat: Int, laneOwner: [Int: Int], view: PlayerView) -> Route? {
        graph.route(from: c.a, to: c.b, seat: seat, laneOwner: laneOwner, playerCount: view.seats.count)
    }

    /// The seat's route cost for a Contract, nil when it can no longer be joined.
    private func cost(_ c: Contract, seat: Int, laneOwner: [Int: Int], view: PlayerView) -> Int? {
        route(c, seat: seat, laneOwner: laneOwner, view: view)?.cost
    }
}
