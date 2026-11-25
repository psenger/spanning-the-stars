import Testing
@testable import StarsCore

/// The tiny map with its four Contracts listed twice, so a 2-seat setup has enough to offer.
/// Ids 0 to 3 are A-C (5), A-D (6), B-F (7), A-E (6).
private let map: GalaxyMap = {
    let t = GalaxyMap.tiny
    let pairs = [("A", "C"), ("A", "D"), ("B", "F"), ("A", "E")]
    return GalaxyMap(systems: t.systems, lanes: t.lanes,
                     contractPairs: (pairs + pairs).map { (a: $0.0, b: $0.1, flavor: "t") })
}()
private let engine = GameEngine(map: map)

private func newGame() -> GameState {
    engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 7,
                              kinds: [.bot(.pilot), .bot(.pilot)]))
}

/// Setup done; the current seat holds exactly `contracts` and `cards`.
private func playing(contracts: [Int], cards: [Card: Int]) -> GameState {
    var s = newGame()
    while case let .setupContracts(offered) = s.phase {
        _ = try! engine.apply(.keepContracts(Array(offered.prefix(2))), to: &s)
    }
    var hand = Hand()
    for (card, n) in cards { hand.add(card, n) }
    s.players[s.current].hand = hand
    s.players[s.current].contracts = contracts
    return s
}

private func pilot(mistakeRate: Double = 0) -> HeuristicBot {
    var settings = BotSettings.level(.pilot)
    settings.temperature = 0
    settings.mistakeRate = mistakeRate
    return HeuristicBot(settings: settings, map: map)
}

private func choice(_ bot: HeuristicBot, _ s: GameState, seed: UInt64 = 1) -> Action {
    var rng = SeededRNG(seed: seed)
    return bot.chooseAction(view: PlayerView(state: s, seat: s.current, engine: engine), rng: &rng, deadline: nil)
}

@Suite struct PilotTests {
    @Test func pilotSettingsUseThePlannerOnly() {
        let s = BotSettings.level(.pilot)
        #expect(s.usesPlanner && !s.usesScorer && !s.usesOpponentModel && s.playouts == 0)
        #expect(s.temperature > 0 && s.mistakeRate > 0 && s.mistakeRate < 1)
        #expect(BotRoster(engine: engine).bot(.pilot) is HeuristicBot)
    }

    @Test func goalsAreTheUnfulfilledContractsWithTheirRoutes() {
        // Contracts A-C, A-D and B-F. The seat owns A-B and B-C; the rival owns E-F and A-F, so F is cut off.
        var s = playing(contracts: [0, 1, 2], cards: [:])
        let seat = s.current
        s.players[seat].lanes = [0, 1]
        s.laneOwner = [0: seat, 1: seat, 5: 1 - seat, 6: 1 - seat]
        let goals = pilot().goals(view: PlayerView(state: s, seat: seat, engine: engine))
        #expect(goals == [Goal(contractID: 1, value: 6, route: Route(toClaim: [2], cost: 1)),
                          Goal(contractID: 2, value: 7, route: nil)])
    }

    @Test func claimsAWantedLaneItCanPayFor() {
        // Contract A-C wants A-B (red 2) and B-C (open 3).
        let s = playing(contracts: [0], cards: [.resource(.red): 2])
        let claim = Action.claim(laneID: 0, payment: Payment([.resource(.red): 2]))
        #expect(choice(pilot(), s) == claim)
        let scored = pilot().scoredActions(view: PlayerView(state: s, seat: s.current, engine: engine))
        #expect(scored.first?.action == claim)
        #expect(scored.first?.score == 8)   // wantedClaim 6 + 2 points
    }

    @Test func offPlanClaimsPayAPenalty() {
        // Contract A-C; the hand pays for B-E (black 4, 7 points), which no route uses.
        let s = playing(contracts: [0], cards: [.resource(.black): 4])
        let scored = pilot().scoredActions(view: PlayerView(state: s, seat: s.current, engine: engine))
        let offPlan = Action.claim(laneID: 7, payment: Payment([.resource(.black): 4]))
        #expect(scored.first { $0.action == offPlan }?.score == 3)   // 7 points - offPlanPenalty 4
        // B-C is wanted and open: the black cards pay for it too.
        #expect(scored.first?.action == .claim(laneID: 1, payment: Payment([.resource(.black): 3])))
        #expect(scored.first?.score == 10)   // wantedClaim 6 + 4 points
    }

    @Test func fewestCoresPaymentScoresHighest() {
        let s = playing(contracts: [0], cards: [.resource(.red): 2, .core: 2])
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        let scored = pilot().scoredActions(view: view)
        let lane0 = scored.filter { if case .claim(laneID: 0, _) = $0.action { true } else { false } }
        #expect(lane0.map(\.action) == [
            .claim(laneID: 0, payment: Payment([.resource(.red): 2])),
            .claim(laneID: 0, payment: Payment([.resource(.red): 1, .core: 1])),
            .claim(laneID: 0, payment: Payment([.core: 2])),
        ])
        #expect(lane0[0].score > lane0[1].score && lane0[1].score > lane0[2].score)
    }

    @Test func drawsTheExchangeCardItNeeds() {
        var s = playing(contracts: [0], cards: [:])
        s.exchange = [.resource(.blue), .resource(.green), .resource(.red), .resource(.yellow), .resource(.purple)]
        #expect(choice(pilot(), s) == .drawExchange(slot: 2))
        let scored = pilot().scoredActions(view: PlayerView(state: s, seat: s.current, engine: engine))
        #expect(scored.first?.score == 2.5)                                  // draw 1 + cardNeed 3 * 1/2
        #expect(scored.first { $0.action == .drawBlind }?.score == 1.9)      // draw 1 + cardNeed 3 * 0.3
        #expect(scored.first { $0.action == .drawContracts }?.score == -2)
    }

    @Test func keepsTheContractsItCanReach() {
        // The rival owns E-F and A-F, so F is cut off and Contract 2 (B-F) cannot be completed.
        var s = newGame()
        s.phase = .setupContracts(offered: [0, 1, 2, 3])
        s.laneOwner = [5: 1 - s.current, 6: 1 - s.current]
        #expect(choice(pilot(), s) == .keepContracts([0, 1, 3]))
        let scored = pilot().scoredActions(view: PlayerView(state: s, seat: s.current, engine: engine))
        #expect(scored.count == 11)
        #expect(scored.first?.score == 8.5)   // (5 - 2.5) + (6 - 3) + (6 - 3)
        #expect(scored.first { $0.action == .keepContracts([0, 2]) }?.score == -4.5)   // 2.5 - 7
    }

    @Test func keepsTheFewestContractsOnATie() {
        var settings = BotSettings.level(.pilot)
        settings.temperature = 0
        settings.mistakeRate = 0
        settings.weights.keepCostWeight = 1   // value - cost is 0 for every Contract on an empty board
        let bot = HeuristicBot(settings: settings, map: map)
        var s = newGame()
        s.phase = .setupContracts(offered: [0, 1, 2, 3])
        #expect(choice(bot, s) == .keepContracts([0, 1]))   // every subset scores 0: the minimum of 2
        s.phase = .choosingContracts(offered: [0, 1, 3])
        #expect(choice(bot, s) == .keepContracts([0]))      // after a draw the minimum is 1
        // The rival owns A-B and A-F, so A is cut off: the cheapest single loss is kept.
        s.laneOwner = [0: 1 - s.current, 6: 1 - s.current]
        #expect(choice(pilot(), s) == .keepContracts([0]))
    }

    @Test func aMistakeDropsAGoalForThatDecision() {
        let s = playing(contracts: [0], cards: [.resource(.red): 2])
        let view = PlayerView(state: s, seat: s.current, engine: engine)
        // With its only goal dropped, the claim of A-B is off plan (2 - 4) and a blind draw wins.
        #expect(choice(pilot(mistakeRate: 1), s) == .drawBlind)
        // scoredActions never applies mistakes.
        #expect(pilot(mistakeRate: 1).scoredActions(view: view).first?.action
                == .claim(laneID: 0, payment: Payment([.resource(.red): 2])))
    }

    @Test func neverPicksAnIllegalAction() async {
        // 304 Pilot-only games on the standard map: 2 to 5 Houses, hazards off and on, 38 games each.
        for players in 2...5 {
            for hazards in [false, true] {
                let r = await runMatch(levels: Array(repeating: .pilot, count: players), games: 38,
                                       seed: UInt64(players * 100), hazards: hazards)
                #expect(r.illegalMoves == 0, "\(players) Houses, hazards \(hazards)")
                #expect(r.avgTurns > 0)
            }
        }
    }

    @Test func pilotBeatsCadetInAShortMatch() async {
        let r = await runMatch(levels: [.pilot, .cadet], games: 60, seed: 9)
        #expect(r.stats.last!.level == .pilot)
        #expect(r.stats.last!.winRate > 0.6)     // smoke check; the 2,000-game run is in docs/ai-results.md
    }
}
