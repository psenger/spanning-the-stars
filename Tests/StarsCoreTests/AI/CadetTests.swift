import Testing
@testable import StarsCore

private let engine = GameEngine(map: .big)

/// A 2-seat game on the fixture map with setup done: each seat keeps its first 2 offered Contracts.
private func playing(seed: UInt64) -> GameState {
    var s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: seed,
                                      kinds: [.bot(.cadet), .bot(.cadet)]))
    while case let .setupContracts(offered) = s.phase {
        _ = try! engine.apply(.keepContracts(Array(offered.prefix(2))), to: &s)
    }
    return s
}

private func cadet(temperature: Double = 2.0) -> HeuristicBot {
    var settings = BotSettings.level(.cadet)
    settings.temperature = temperature
    return HeuristicBot(settings: settings, map: engine.map)
}

@Suite struct CadetTests {
    @Test func cadetSettingsAreTheStartingValues() {
        let s = BotSettings.level(.cadet)
        #expect(!s.usesPlanner && !s.usesScorer && !s.usesOpponentModel)
        #expect(s.temperature == 2.0 && s.mistakeRate == 0 && s.playouts == 0)
        #expect(s.weights == BotWeights())
        #expect(BotWeights().pointsNow == 1.0 && BotWeights().draw == 1.0 && BotWeights().newContracts == -2.0)
    }

    @Test func cadetPrefersBigClaimsAtZeroTemperature() {
        var s = playing(seed: 7)
        var hand = Hand()
        hand.add(.resource(.white), 6)   // pays for lane 6 (length 6, white) and the open lane 1
        s.players[s.current].hand = hand
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let big = Action.claim(laneID: 6, payment: Payment([.resource(.white): 6]))
        #expect(view.legalActions.contains(big))
        #expect(view.legalActions.contains(.drawBlind))

        let scored = cadet().scoredActions(view: view)
        #expect(scored.count == view.legalActions.count)
        #expect(scored.first?.action == big)
        #expect(scored.first?.score == 15)
        // best first, and equal scores keep their order in legalActions
        for (a, b) in zip(scored, scored.dropFirst()) {
            #expect(a.score >= b.score)
            if a.score == b.score {
                #expect(view.legalActions.firstIndex(of: a.action)! < view.legalActions.firstIndex(of: b.action)!)
            }
        }
        #expect(scored.first { $0.action == .drawBlind }?.score == 1)
        #expect(scored.first { $0.action == .drawContracts }?.score == -2)

        var rng = SeededRNG(seed: 1)
        #expect(cadet(temperature: 0).chooseAction(view: view, rng: &rng, deadline: nil) == big)
    }

    @Test func cadetScoresKeepingFewerContractsHigher() {
        let s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 7,
                                          kinds: [.bot(.cadet), .bot(.cadet)]))
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let scored = cadet().scoredActions(view: view)
        #expect(scored.count == view.legalActions.count)
        for entry in scored {
            guard case let .keepContracts(ids) = entry.action else {
                Issue.record("setup offers only keepContracts")
                continue
            }
            #expect(entry.score == -Double(ids.count))
        }
        #expect(scored.first?.score == -2)
    }

    @Test func cadetMustPassWhenOnlyPassIsLegal() {
        var s = playing(seed: 7)
        s.depot = []
        s.salvage = []
        s.exchange = Array(repeating: nil, count: 5)
        s.contractDeck = []
        s.players[s.current].hand = Hand()
        #expect(engine.legalActions(s) == [.pass])

        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let scored = cadet().scoredActions(view: view)
        #expect(scored.count == 1 && scored[0].action == .pass && scored[0].score == 0)
        var rng = SeededRNG(seed: 1)
        #expect(cadet().chooseAction(view: view, rng: &rng, deadline: nil) == .pass)
        #expect(BotDriver(engine: engine).decide(s) == BotDecision(action: .pass, substituted: false))
    }

    @Test func softmaxAtZeroTemperatureIsArgmax() {
        let scored: [(action: Action, score: Double)] = [
            (.drawBlind, 1), (.drawExchange(slot: 0), 5), (.drawExchange(slot: 1), 5),
        ]
        for seed in UInt64(1)...20 {
            var rng = SeededRNG(seed: seed)
            #expect(softmaxPick(scored, temperature: 0, rng: &rng) == .drawExchange(slot: 0))
        }
    }

    @Test func softmaxSpreadsAtHighTemperature() {
        let scored: [(action: Action, score: Double)] = [(.drawBlind, 5), (.drawContracts, 0)]
        var rng = SeededRNG(seed: 3)
        var first = 0
        for _ in 0..<2000 where softmaxPick(scored, temperature: 100, rng: &rng) == .drawBlind { first += 1 }
        #expect(first > 800 && 2000 - first > 800)
    }

    @Test func softmaxFavorsHighScoresAtLowTemperature() {
        let scored: [(action: Action, score: Double)] = [(.drawBlind, 5), (.drawContracts, 0)]
        var rng = SeededRNG(seed: 3)
        var first = 0
        for _ in 0..<2000 where softmaxPick(scored, temperature: 1, rng: &rng) == .drawBlind { first += 1 }
        #expect(first > 1900 && first < 2000)   // e^5 to 1, about 99.3%
    }

    @Test func rosterGivesCadetTheHeuristicBot() {
        #expect(BotRoster(engine: engine).bot(.cadet) is HeuristicBot)
        for level in BotLevel.allCases { #expect(!(BotRoster(engine: engine).bot(level) is RandomBot)) }
    }
}
