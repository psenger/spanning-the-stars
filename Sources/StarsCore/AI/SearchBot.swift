/// A full state consistent with the view, hidden parts sampled. Precondition: the phase is not setupContracts.
/// Guarantee: PlayerView(state: result, seat: view.seat, engine: engine) == view.
func determinize(_ view: PlayerView, engine: GameEngine, model: OpponentModel, rng: inout SeededRNG) -> GameState {
    let rivals = view.seats.indices.filter { $0 != view.seat }
    return determinize(view, engine: engine, guesses: rivals.map { model.likelyContracts(of: $0, view: view) },
                       rng: &rng)
}

/// `determinize` over guesses worked out before: `likelyContracts` of each rival, in seat order.
func determinize(_ view: PlayerView, engine: GameEngine, guesses: [[ContractGuess]],
                 rng: inout SeededRNG) -> GameState {
    // The unknown cards: the deck less the viewer's hand and the Exchange.
    var seen = view.hand.counts
    for card in view.exchange.compactMap({ $0 }) { seen[card, default: 0] += 1 }
    var cards = standardDeck().filter { card in
        guard let n = seen[card], n > 0 else { return true }
        seen[card] = n - 1
        return false
    }
    cards.shuffle(using: &rng)

    // Contracts the viewer neither holds nor was offered, in id order.
    var offered: [Int] = []
    if case let .choosingContracts(ids) = view.phase { offered = ids }
    var pool = engine.map.contracts.map(\.id).filter { !view.contracts.contains($0) && !offered.contains($0) }

    var guesses = guesses[...]
    let players = view.seats.enumerated().map { seat, s in
        var hand = view.hand, contracts = view.contracts
        if seat != view.seat {
            hand = Hand()
            for _ in 0..<s.handCount { hand.add(cards.removeLast()) }
            // Drawn without replacement, weighted by the opponent model.
            var weight = [Double](repeating: 0, count: engine.map.contracts.count)
            for guess in guesses.removeFirst() { weight[guess.contractID] = guess.likelihood }
            contracts = (0..<s.contractCount).map { _ in
                var roll = Double.random(in: 0..<pool.reduce(0) { $0 + weight[$1] }, using: &rng)
                let pick = pool.firstIndex { id in
                    roll -= weight[id]
                    return roll < 0
                } ?? pool.count - 1   // rounding left the roll past the last weight
                return pool.remove(at: pick)
            }
        }
        return PlayerState(house: s.house, kind: s.kind, hand: hand, contracts: contracts,
                           beacons: s.beacons, score: s.score, lanes: s.lanes)
    }

    // The rest is the Contract deck; what is over is the offer a rival is choosing from.
    pool.shuffle(using: &rng)
    var phase = view.phase
    if case .choosingContracts = phase, view.current != view.seat {
        phase = .choosingContracts(offered: Array(pool.dropFirst(view.contractDeckCount)))
    }
    let config = GameConfig(houses: view.seats.map(\.house), frontierHazards: view.hazards, seed: rng.next(),
                            kinds: view.seats.map(\.kind))
    return GameState(
        config: config, players: players, current: view.current, firstPlayer: view.firstPlayer, phase: phase,
        depot: Array(cards.dropFirst(view.salvageCount)), exchange: view.exchange,
        salvage: Array(cards.prefix(view.salvageCount)),
        contractDeck: Array(pool.prefix(view.contractDeckCount)), pendingOffers: [], setupReturns: [],
        laneOwner: view.laneOwner, finalTurnsRemaining: view.finalTurnsRemaining,
        consecutivePasses: view.consecutivePasses, rng: SeededRNG(seed: rng.next()), log: view.log)
}

/// Admiral: ranks the legal actions as the Commander does, then plays each of the best few to the
/// end of the game on sampled full states and keeps the one with the best mean result.
public struct SearchBot: Bot {
    /// How many of the Commander's best actions are searched.
    static let candidates = 6
    /// Softmax temperature of the playout policy.
    static let playoutTemperature = 0.3

    private let settings: BotSettings
    private let engine: GameEngine
    private let commander: HeuristicBot
    private let playoutBot: HeuristicBot   // Navigator: about 5 times cheaper than Commander
    private let model: OpponentModel

    public init(settings: BotSettings, engine: GameEngine) {
        self.settings = settings
        self.engine = engine
        commander = HeuristicBot(settings: settings, map: engine.map)
        var playout = BotSettings.level(.navigator)
        playout.temperature = Self.playoutTemperature
        playout.mistakeRate = 0
        playoutBot = HeuristicBot(settings: playout, map: engine.map)
        model = OpponentModel(graph: MapGraph(map: engine.map))
    }

    public func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action {
        let ranked = commander.scoredActions(view: view).map(\.action)
        if case .setupContracts = view.phase { return ranked[0] }
        // A lane's other payments only spend more Cores.
        var lanes: Set<Int> = []
        let candidates = ranked.filter {
            if case let .claim(id, _) = $0 { lanes.insert(id).inserted } else { true }
        }.prefix(Self.candidates)
        guard candidates.count > 1 else { return ranked[0] }

        let rivals = view.seats.indices.filter { $0 != view.seat }
        let guesses = rivals.map { model.likelyContracts(of: $0, view: view) }
        var sum = [Double](repeating: 0, count: candidates.count)
        var count = [Int](repeating: 0, count: candidates.count)
        // Every candidate is played on the same states with the same playout rng.
        search: for _ in 0..<max(1, settings.playouts / Self.candidates) {
            let state = determinize(view, engine: engine, guesses: guesses, rng: &rng)
            let seed = rng.next()
            for (i, action) in candidates.enumerated() {
                guard let result = playout(action, from: state, seat: view.seat, rng: SeededRNG(seed: seed),
                                           deadline: deadline) else { break search }
                sum[i] += result
                count[i] += 1
            }
        }
        // Best mean; ties and candidates with no playout keep the Commander's order.
        var best = 0
        for i in candidates.indices where count[i] > 0
            && sum[i] / Double(count[i]) > sum[best] / Double(count[best]) {
            best = i
        }
        return candidates[best]
    }

    /// The seat's result of one game played out after `action`: win credit plus the lead over the
    /// best rival in hundredths. nil when the deadline passes first.
    private func playout(_ action: Action, from state: GameState, seat: Int, rng: SeededRNG,
                         deadline: ContinuousClock.Instant?) -> Double? {
        var s = state, rng = rng
        var next = action
        while true {
            if let deadline, ContinuousClock.now >= deadline { return nil }
            _ = try! engine.apply(next, to: &s)
            if s.phase == .gameOver { break }
            next = playoutBot.chooseAction(view: PlayerView(state: s, seat: s.current, engine: engine),
                                           rng: &rng, deadline: nil)
        }
        let scores = finalScores(s, map: engine.map), winners = ranking(scores)[0]
        let rival = scores.filter { $0.player != seat }.map(\.total).max()!
        return (winners.contains(seat) ? 1 / Double(winners.count) : 0)
            + Double(scores[seat].total - rival) / 100
    }
}
