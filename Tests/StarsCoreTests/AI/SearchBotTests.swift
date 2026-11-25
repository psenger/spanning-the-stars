import Testing
@testable import StarsCore

private let engine = GameEngine(map: .standard)
private let driver = BotDriver(engine: engine)

/// A Navigator game stopped after `actions` actions, setup included.
private func midGame(houses: Int, actions: Int, seed: UInt64) -> GameState {
    var s = engine.newGame(GameConfig(houses: Array(House.allCases.prefix(houses)), frontierHazards: false,
                                      seed: seed, kinds: Array(repeating: .bot(.navigator), count: houses)))
    for _ in 0..<actions {
        guard let decision = driver.decide(s) else { break }
        _ = try! engine.apply(decision.action, to: &s)
    }
    return s
}

/// The Admiral with a smaller playout budget.
private func admiral(playouts: Int) -> SearchBot {
    var settings = BotSettings.level(.admiral)
    settings.playouts = playouts
    return SearchBot(settings: settings, engine: engine)
}

/// The state with every seat an Admiral.
private func allAdmirals(_ state: GameState) -> GameState {
    var s = state
    for i in s.players.indices { s.players[i].kind = .bot(.admiral) }
    return s
}

@Suite struct SearchBotTests {
    @Test func admiralSettingsAreCommanderWithSearch() {
        let s = BotSettings.level(.admiral), c = BotSettings.level(.commander)
        #expect(s.usesPlanner && s.usesScorer && s.usesOpponentModel)
        #expect(s.temperature == 0 && s.mistakeRate == 0 && s.playouts > 0)
        #expect(s.weights == c.weights)
        #expect(BotRoster(engine: engine).bot(.admiral) is SearchBot)
    }

    @Test func determinizedStateMatchesTheView() throws {
        let model = OpponentModel(graph: MapGraph(map: engine.map))
        var rng = SeededRNG(seed: 5)
        var deck = Hand()
        for card in standardDeck() { deck.add(card) }
        /// Every seat's view of `s` gives a sampled state with the same view and a whole deck.
        func check(_ s: GameState) {
            for seat in s.players.indices {
                let view = PlayerView(state: s, seat: seat, engine: engine)
                let d = determinize(view, engine: engine, model: model, rng: &rng)
                #expect(PlayerView(state: d, seat: seat, engine: engine) == view)

                var cards = Hand()
                for card in d.depot + d.salvage + d.exchange.compactMap({ $0 }) { cards.add(card) }
                for p in d.players { for (card, n) in p.hand.counts { cards.add(card, n) } }
                #expect(cards.total == 110 && cards == deck)

                var contracts = d.players.flatMap(\.contracts) + d.contractDeck
                if case let .choosingContracts(offered) = d.phase { contracts += offered }
                #expect(contracts.count == 33 && Set(contracts).count == 33)
                #expect(d.pendingOffers.isEmpty && d.setupReturns.isEmpty)
                // The sampled state is playable: the engine accepts each of its legal actions.
                for action in engine.legalActions(d) {
                    var next = d
                    #expect(throws: Never.self) { _ = try engine.apply(action, to: &next) }
                }
            }
        }

        // 10 games of 2 to 4 Houses still running after 120 actions, each stopped three times.
        var games = 0, seed: UInt64 = 0
        while games < 10 {
            seed += 1
            let houses = 2 + Int(seed % 3)
            guard midGame(houses: houses, actions: 120, seed: seed).phase != .gameOver else { continue }
            games += 1
            for actions in [40, 80, 120] { check(midGame(houses: houses, actions: actions, seed: seed)) }
        }

        // A rival choosing Contracts: its hidden offer is sampled too.
        var choosing = midGame(houses: 3, actions: 80, seed: 3)
        while choosing.phase != .awaitingAction {
            _ = try engine.apply(engine.legalActions(choosing)[0], to: &choosing)
        }
        _ = try engine.apply(.drawContracts, to: &choosing)
        let rival = (choosing.current + 1) % 3
        let hidden = determinize(PlayerView(state: choosing, seat: rival, engine: engine), engine: engine,
                                 model: model, rng: &rng)
        guard case let .choosingContracts(offered) = hidden.phase else {
            Issue.record("expected a Contract choice")
            return
        }
        #expect(offered.count == 3)
        check(choosing)
    }

    @Test func determinizeSamplesTheHiddenParts() {
        // Two samples of one view differ in what the viewer cannot see.
        let s = midGame(houses: 3, actions: 80, seed: 4)
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let model = OpponentModel(graph: MapGraph(map: engine.map))
        var rng = SeededRNG(seed: 9)
        let a = determinize(view, engine: engine, model: model, rng: &rng)
        let b = determinize(view, engine: engine, model: model, rng: &rng)
        #expect(a.depot != b.depot && a.contractDeck != b.contractDeck)
        #expect(a.config.seed != b.config.seed && a.rng != b.rng)
        #expect(a.config.seed != s.config.seed && a.rng != s.rng)
        // Equal rngs give equal samples.
        var r1 = SeededRNG(seed: 9), r2 = SeededRNG(seed: 9)
        #expect(determinize(view, engine: engine, model: model, rng: &r1)
                == determinize(view, engine: engine, model: model, rng: &r2))
    }

    @Test func leakTestHiddenStateDoesNotChangeTheMove() throws {
        let a = allAdmirals(midGame(houses: 2, actions: 80, seed: 7))
        #expect(a.phase != .gameOver)
        var b = a
        let seat = a.current, other = 1 - seat
        b.depot.reverse()
        b.contractDeck.reverse()
        b.rng = SeededRNG(seed: 999)
        // swap the rival's hand with the same number of depot cards
        let n = b.players[other].hand.total
        var newHand = Hand()
        for _ in 0..<n { newHand.add(b.depot.removeLast()) }
        for (card, count) in b.players[other].hand.counts { b.depot += Array(repeating: card, count: count) }
        b.players[other].hand = newHand
        b.players[other].contracts = Array(b.contractDeck.suffix(b.players[other].contracts.count))
        #expect(a.players[other].hand != b.players[other].hand)
        #expect(a.players[other].contracts != b.players[other].contracts)
        #expect(a.depot != b.depot && a.contractDeck != b.contractDeck)
        #expect(engine.legalActions(a).count > 1)   // the move is searched, not forced

        let move = try #require(driver.decide(a))
        #expect(!move.substituted)
        #expect(driver.decide(b) == move)
    }

    @Test func sameViewAndSeedGiveTheSameMove() {
        let s = midGame(houses: 3, actions: 80, seed: 3)
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        #expect(view.legalActions.count > 1)
        let bot = admiral(playouts: 12)
        var r1 = SeededRNG(seed: 21), r2 = SeededRNG(seed: 21)
        let first = bot.chooseAction(view: view, rng: &r1, deadline: nil)
        #expect(first == bot.chooseAction(view: view, rng: &r2, deadline: nil))
        #expect(r1 == r2)
    }

    @Test func returnsALegalActionInEveryPhase() throws {
        let bot = admiral(playouts: 12)
        var rng = SeededRNG(seed: 2)
        func check(_ s: GameState, _ label: Comment) {
            let view = PlayerView(state: s, seat: s.current, engine: engine)
            #expect(!view.legalActions.isEmpty, label)
            #expect(view.legalActions.contains(bot.chooseAction(view: view, rng: &rng, deadline: nil)), label)
        }

        // setup pick: the Commander's choice
        let setup = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 7,
                                              kinds: [.bot(.admiral), .bot(.admiral)]))
        let setupView = PlayerView(state: setup, seat: setup.current, engine: engine)
        let commander = HeuristicBot(settings: .level(.admiral), map: engine.map)
        #expect(bot.chooseAction(view: setupView, rng: &rng, deadline: nil)
                == commander.scoredActions(view: setupView)[0].action)

        let first = midGame(houses: 2, actions: 60, seed: 7)
        var turn = first
        while turn.phase != .awaitingAction { _ = try engine.apply(engine.legalActions(turn)[0], to: &turn) }
        check(turn, "first draw")

        var second = turn
        _ = try engine.apply(.drawBlind, to: &second)
        #expect(second.phase == .drawingSecondCard)
        check(second, "second draw")

        var choosing = turn
        _ = try engine.apply(.drawContracts, to: &choosing)
        guard case .choosingContracts = choosing.phase else {
            Issue.record("expected a Contract choice")
            return
        }
        check(choosing, "contract choice")

        var stuck = turn
        stuck.depot = []
        stuck.salvage = []
        stuck.exchange = Array(repeating: nil, count: 5)
        stuck.contractDeck = []
        stuck.players[stuck.current].hand = Hand()
        #expect(engine.legalActions(stuck) == [.pass])
        check(stuck, "pass only")
    }

    @Test func picksTheBestLastMoveWhereTheCommanderDoesNot() throws {
        // On the last turn of the game the result of every move is certain, so the search must do at
        // least as well as the Commander's first choice, and better where that choice is not the best.
        let commander = HeuristicBot(settings: .level(.admiral), map: engine.map)
        let bot = admiral(playouts: 12)
        var rng = SeededRNG(seed: 1)
        var better = 0
        for seed in UInt64(1)...12 {
            var s = midGame(houses: 2, actions: 100, seed: seed)
            while s.phase != .awaitingAction { _ = try engine.apply(engine.legalActions(s)[0], to: &s) }
            let seat = s.current
            s.finalTurnsRemaining = 1
            s.contractDeck = []
            /// The seat's result when the game ends after `action`; a draw changes no score.
            func result(_ action: Action) throws -> Double {
                var end = s
                if case .claim = action { _ = try engine.apply(action, to: &end) }
                let scores = finalScores(end, map: engine.map), winners = ranking(scores)[0]
                return (winners.contains(seat) ? 1 / Double(winners.count) : 0)
                    + Double(scores[seat].total - scores[1 - seat].total) / 100
            }
            let view = PlayerView(state: s, seat: seat, engine: engine)
            let plain = try result(commander.scoredActions(view: view)[0].action)
            let searched = try result(bot.chooseAction(view: view, rng: &rng, deadline: nil))
            #expect(searched >= plain, "seed \(seed)")
            if searched > plain { better += 1 }
        }
        #expect(better > 0)
    }

    @Test func staysWithinItsDeadline() {
        let s = midGame(houses: 4, actions: 120, seed: 5)
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        #expect(view.legalActions.count > 1)
        let bot = SearchBot(settings: .level(.admiral), engine: engine)
        var rng = SeededRNG(seed: 4)
        let clock = ContinuousClock()
        let start = clock.now
        let action = bot.chooseAction(view: view, rng: &rng, deadline: start + .seconds(1.5))
        #expect(clock.now - start < .seconds(1.75))
        #expect(view.legalActions.contains(action))
    }

    @Test func aPassedDeadlineGivesTheCommanderChoice() {
        let s = midGame(houses: 2, actions: 80, seed: 7)
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let commander = HeuristicBot(settings: .level(.admiral), map: engine.map)
        var rng = SeededRNG(seed: 4)
        let action = admiral(playouts: 12).chooseAction(view: view, rng: &rng, deadline: ContinuousClock.now)
        #expect(action == commander.scoredActions(view: view)[0].action)
    }

    @Test func admiralGamesFinishLegally() async {
        let roster = BotRoster { level in
            if level == .admiral { return admiral(playouts: 6) }
            return HeuristicBot(settings: .level(level), map: engine.map)
        }
        let small = BotDriver(engine: engine, roster: roster)
        let results = await withTaskGroup(of: GameResult.self) { group in
            for g in 0..<6 {
                group.addTask {
                    let kinds: [PlayerKind] = g.isMultiple(of: 2) ? [.bot(.admiral), .bot(.commander)]
                        : [.bot(.commander), .bot(.admiral)]
                    return playGame(config: GameConfig(houses: [.varn, .solace], frontierHazards: false,
                                                       seed: UInt64(100 + g), kinds: kinds),
                                    engine: engine, driver: small)
                }
            }
            var all: [GameResult] = []
            for await r in group { all.append(r) }
            return all
        }
        #expect(results.count == 6)
        for r in results {
            #expect(r.state.phase == TurnPhase.gameOver)
            #expect(r.illegalMoves == 0)
        }
    }
}
