public struct GameEngine: Sendable {
    public let map: GalaxyMap

    public init(map: GalaxyMap) { self.map = map }

    public func newGame(_ config: GameConfig) -> GameState {
        precondition(config.kinds == nil || config.kinds?.count == config.houses.count,
                     "GameConfig.kinds needs one entry per House")
        var rng = SeededRNG(seed: config.seed)
        var deck = standardDeck()
        deck.shuffle(using: &rng)

        var players: [PlayerState] = config.houses.enumerated().map { i, house in
            PlayerState(house: house, kind: config.kinds?[i] ?? .human, hand: Hand(), contracts: [])
        }
        for i in players.indices {
            for _ in 0..<4 { players[i].hand.add(deck.removeLast()) }
        }

        var contractIDs = map.contracts.map(\.id)
        contractIDs.shuffle(using: &rng)
        var offers: [[Int]] = []
        for _ in players.indices {
            offers.append((0..<4).map { _ in contractIDs.removeLast() })
        }

        let first = Int.random(in: 0..<players.count, using: &rng)
        var state = GameState(
            config: config, players: players, current: 0, firstPlayer: first,
            phase: .setupContracts(offered: offers[0]),
            depot: deck, exchange: Array(repeating: nil, count: 5), salvage: [],
            contractDeck: contractIDs, pendingOffers: offers, setupReturns: [],
            laneOwner: [:], finalTurnsRemaining: nil, consecutivePasses: 0,
            rng: rng, log: [])
        _ = refillExchange(&state)
        return state
    }

    /// Later tasks add the individual actions.
    public func apply(_ action: Action, to state: inout GameState) throws(RuleError) -> [GameEvent] {
        let events = try dispatch(action, to: &state)
        state.log += events
        return events
    }

    private func dispatch(_ action: Action, to state: inout GameState) throws(RuleError) -> [GameEvent] {
        if state.phase == .gameOver { throw .gameOver }
        switch (state.phase, action) {
        case let (.setupContracts(offered), .keepContracts(ids)):
            return try keepSetupContracts(ids, offered: offered, state: &state)
        case (.awaitingAction, .drawBlind), (.drawingSecondCard, .drawBlind):
            return try drawBlind(&state)
        case let (.awaitingAction, .drawExchange(slot)), let (.drawingSecondCard, .drawExchange(slot)):
            return try drawExchange(slot, &state)
        case let (.awaitingAction, .claim(laneID, payment)):
            return try claim(laneID, payment, &state)
        case (.awaitingAction, .drawContracts):
            return try drawContracts(&state)
        case (.awaitingAction, .pass):
            return try passAction(&state)
        case let (.choosingContracts(offered), .keepContracts(ids)):
            return try keepDrawnContracts(ids, offered: offered, state: &state)
        default:
            throw .wrongPhase
        }
    }

    /// Grows task by task; phases not yet implemented have no legal actions.
    public func legalActions(_ state: GameState) -> [Action] {
        switch state.phase {
        case let .setupContracts(offered): return keepSubsets(of: offered, minimum: 2)
        case .awaitingAction:
            let actions = drawActions(state) + claimActions(state) + (state.contractDeck.isEmpty ? [] : [.drawContracts])
            return actions.isEmpty ? [.pass] : actions
        case let .choosingContracts(offered): return keepSubsets(of: offered, minimum: 1)
        case .drawingSecondCard: return drawActions(state)
        default: return []
        }
    }
}
