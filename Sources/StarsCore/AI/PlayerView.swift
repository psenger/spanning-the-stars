/// What every seat may know about one player.
public struct SeatView: Sendable, Equatable {
    public let house: House
    public let kind: PlayerKind
    public let handCount: Int
    public let contractCount: Int
    public let beacons: Int
    public let score: Int
    public let lanes: [Int]
}

/// The game as one seat sees it: its own hand and Contracts, and public information only
/// about everything else. Holds no `GameState`, seed or RNG.
public struct PlayerView: Sendable, Equatable {
    public let seat: Int
    public let hazards: Bool
    public let seats: [SeatView]
    public let current: Int
    public let firstPlayer: Int
    /// Offered ids are emptied when `seat` is not the current seat.
    public let phase: TurnPhase
    public let hand: Hand
    public let contracts: [Int]
    public let exchange: [Card?]
    public let depotCount: Int
    public let salvageCount: Int
    public let contractDeckCount: Int
    public let laneOwner: [Int: Int]
    public let finalTurnsRemaining: Int?
    public let consecutivePasses: Int
    public let log: [GameEvent]
    /// The engine's legal actions when `seat` is the current seat, else empty.
    public let legalActions: [Action]

    public init(state: GameState, seat: Int, engine: GameEngine) {
        let isCurrent = seat == state.current
        self.seat = seat
        hazards = state.config.frontierHazards
        seats = state.players.map {
            SeatView(house: $0.house, kind: $0.kind, handCount: $0.hand.total,
                     contractCount: $0.contracts.count, beacons: $0.beacons, score: $0.score, lanes: $0.lanes)
        }
        current = state.current
        firstPlayer = state.firstPlayer
        switch state.phase {
        case .setupContracts where !isCurrent: phase = .setupContracts(offered: [])
        case .choosingContracts where !isCurrent: phase = .choosingContracts(offered: [])
        default: phase = state.phase
        }
        hand = state.players[seat].hand
        contracts = state.players[seat].contracts
        exchange = state.exchange
        depotCount = state.depot.count
        salvageCount = state.salvage.count
        contractDeckCount = state.contractDeck.count
        laneOwner = state.laneOwner
        finalTurnsRemaining = state.finalTurnsRemaining
        consecutivePasses = state.consecutivePasses
        log = state.log
        legalActions = isCurrent ? engine.legalActions(state) : []
    }

    /// The engine's claim guard for any seat, from public information.
    public func claimBlocker(_ lane: Lane, seat: Int) -> RuleError? {
        StarsCore.claimBlocker(lane, seat: seat, laneOwner: laneOwner, playerCount: seats.count,
                               beacons: seats[seat].beacons, hazards: hazards)
    }
}
