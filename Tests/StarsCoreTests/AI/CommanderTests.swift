import Testing
@testable import StarsCore

/// The tiny map with its four Contracts listed twice, so a 2-seat setup has enough to offer.
/// Ids 0 to 3 are A-C (5), A-D (6), B-F (7), A-E (6); ids 4 to 7 repeat them.
private let map: GalaxyMap = {
    let t = GalaxyMap.tiny
    let pairs = [("A", "C"), ("A", "D"), ("B", "F"), ("A", "E")]
    return GalaxyMap(systems: t.systems, lanes: t.lanes,
                     contractPairs: (pairs + pairs).map { (a: $0.0, b: $0.1, flavor: "t") })
}()

/// A chain A-B-C-D-E of four lanes of length 5 (ids 0 to 3) and, apart from it, F-G (lane 4) and
/// G-H (lane 5), both of length 2. Every Contract is A-E.
private let spanMap: GalaxyMap = {
    let names = ["A", "B", "C", "D", "E", "F", "G", "H"]
    let systems = names.enumerated().map { i, n in
        StarSystem(id: n, name: n, region: .coreWorlds, x: Double(i), y: 0)
    }
    let ends = [("A", "B", 5), ("B", "C", 5), ("C", "D", 5), ("D", "E", 5), ("F", "G", 2), ("G", "H", 2)]
    let lanes = ends.enumerated().map { i, e in
        Lane(id: i, a: e.0, b: e.1, length: e.2, color: .color(.red), hazard: .none, twinID: nil)
    }
    return GalaxyMap(systems: systems, lanes: lanes,
                     contractPairs: (0..<8).map { _ in (a: "A", b: "E", flavor: "t") })
}()

/// The tiny map with its four Contracts listed four times: enough to offer a 4-seat setup.
private let crowdMap: GalaxyMap = {
    let t = GalaxyMap.tiny
    let pairs = [("A", "C"), ("A", "D"), ("B", "F"), ("A", "E")]
    return GalaxyMap(systems: t.systems, lanes: t.lanes,
                     contractPairs: (0..<4).flatMap { _ in pairs }.map { (a: $0.0, b: $0.1, flavor: "t") })
}()

/// Setup done; the current seat holds exactly `contracts` and `cards`.
private func playing(on map: GalaxyMap = map, houses: Int = 2, contracts: [Int] = [],
                     cards: [Card: Int]) -> GameState {
    let engine = GameEngine(map: map)
    var s = engine.newGame(GameConfig(houses: Array(House.allCases.prefix(houses)), frontierHazards: false,
                                      seed: 7, kinds: Array(repeating: .bot(.commander), count: houses)))
    while case let .setupContracts(offered) = s.phase {
        _ = try! engine.apply(.keepContracts(Array(offered.prefix(2))), to: &s)
    }
    var hand = Hand()
    for (card, n) in cards { hand.add(card, n) }
    s.players[s.current].hand = hand
    s.players[s.current].contracts = contracts
    return s
}

/// `seat` owns `lanes`.
private func own(_ lanes: [Int], seat: Int, in s: inout GameState) {
    s.players[seat].lanes += lanes
    for id in lanes { s.laneOwner[id] = seat }
}

/// The level's bot with temperature and mistake rate 0.
private func bot(_ level: BotLevel, on map: GalaxyMap = map, weights: BotWeights? = nil) -> HeuristicBot {
    var settings = BotSettings.level(level)
    settings.temperature = 0
    settings.mistakeRate = 0
    if let weights { settings.weights = weights }
    return HeuristicBot(settings: settings, map: map)
}

private func view(_ s: GameState, on map: GalaxyMap = map) -> PlayerView {
    PlayerView(state: s, seat: s.current, engine: GameEngine(map: map))
}

private func claim(_ lane: Int, _ color: ResourceColor, _ n: Int) -> Action {
    .claim(laneID: lane, payment: Payment([.resource(color): n]))
}

private func score(_ action: Action, _ bot: HeuristicBot, _ view: PlayerView) -> Double {
    bot.scoredActions(view: view).first { $0.action == action }!.score
}

@Suite struct CommanderTests {
    @Test func commanderSettingsAddTheOpponentModel() {
        let s = BotSettings.level(.commander), n = BotSettings.level(.navigator)
        #expect(s.usesPlanner && s.usesScorer && s.usesOpponentModel && s.playouts == 0)
        #expect(s.temperature > 0 && s.temperature < n.temperature)
        #expect(s.mistakeRate > 0 && s.mistakeRate < n.mistakeRate)
        let w = BotWeights()
        #expect(w.block == 0.6 && w.span == 0.5 && w.spanReach == 6 && w.closeOut == 5 && w.closeOutLead == 10)
        #expect(s.weights.block == 2.0 && s.weights.keepCostWeight == 1.2)   // tuned, see docs/ai-results.md
        #expect(s.weights.blockCrowdScale == 0 && s.weights.holdBackMargin == 8)   // tuned
        #expect(BotRoster(engine: GameEngine(map: map)).bot(.commander) is HeuristicBot)
    }

    @Test func blocksARivalsCriticalLaneWhenItCostsLittle() {
        // No goals of its own. The rival owns A-B, so its likely Contracts A-C and A-D run through B-C
        // (lane 1). Three orange cards pay for B-C and for E-F (lane 5): the same length and points.
        var s = playing(cards: [.resource(.orange): 3])
        own([0], seat: 1 - s.current, in: &s)
        let v = view(s)
        let critical = claim(1, .orange, 3), side = claim(5, .orange, 3)

        // Navigator sees two equal claims off its plan and looks for new Contracts instead.
        let navigator = bot(.navigator)
        #expect(score(critical, navigator, v) == score(side, navigator, v))
        #expect(navigator.scoredActions(view: v).first?.action == .drawContracts)

        let commander = bot(.commander)
        #expect(commander.scoredActions(view: v).first?.action == critical)
        let blockValue = OpponentModel(graph: MapGraph(map: map)).blockValue(laneID: 1, view: v)
        #expect(blockValue > 1)
        // E-F serves none of the rival's five likeliest Contracts; both claims grow the span alike.
        let block = BotSettings.level(.commander).weights.block
        #expect(abs(score(critical, commander, v) - score(side, commander, v) - block * blockValue) < 1e-9)
    }

    @Test func blockTermIsScaledWithThreeOrMoreHouses() {
        // The same position as above with 2 and with 4 Houses: one rival owns A-B.
        var crowded = BotSettings.level(.commander).weights
        crowded.blockCrowdScale = 0.25
        for (houses, scale) in [(2, 1.0), (4, 0.25)] {
            var s = playing(on: crowdMap, houses: houses, cards: [.resource(.orange): 3])
            own([0], seat: (s.current + 1) % houses, in: &s)
            let v = view(s, on: crowdMap)
            let critical = claim(1, .orange, 3), side = claim(5, .orange, 3)
            let blockValue = OpponentModel(graph: MapGraph(map: crowdMap)).blockValue(laneID: 1, view: v)
            #expect(blockValue > 0.5, "\(houses) Houses")
            let commander = bot(.commander, on: crowdMap, weights: crowded)
            let lead = score(critical, commander, v) - score(side, commander, v)
            #expect(abs(lead - crowded.block * scale * blockValue) < 1e-9, "\(houses) Houses")

            // Navigator has no block term, whatever the scale.
            let navigator = bot(.navigator, on: crowdMap)
            var changed = BotSettings.level(.navigator).weights
            changed.blockCrowdScale = 0
            #expect(navigator.scoredActions(view: v).map(\.score)
                    == bot(.navigator, on: crowdMap, weights: changed).scoredActions(view: v).map(\.score))
            #expect(score(critical, navigator, v) == score(side, navigator, v))
        }
    }

    @Test func blockTermIgnoresARivalWithNoLanes() {
        // With no lanes claimed the guess is flat and names the lowest Contract ids: it is not used.
        let s = playing(cards: [.resource(.orange): 3])
        let v = view(s)
        #expect(OpponentModel(graph: MapGraph(map: map)).blockValue(laneID: 1, view: v) > 0)
        let commander = bot(.commander)
        #expect(score(claim(1, .orange, 3), commander, v) == score(claim(5, .orange, 3), commander, v))
    }

    @Test func extendsTheLongestSpanWhenInReach() {
        // No goals. The seat owns A-F (6). D-E (lane 4) and E-F (lane 5) are both length 3 and payable;
        // only E-F joins the trail, taking it to 9. Too few beacons to want new Contracts.
        var s = playing(cards: [.resource(.purple): 3, .resource(.orange): 3])
        let seat = s.current
        own([6], seat: seat, in: &s)
        s.players[seat].beacons = 14
        let v = view(s)
        let apart = claim(4, .purple, 3), joined = claim(5, .orange, 3)

        let navigator = bot(.navigator)
        #expect(score(apart, navigator, v) == score(joined, navigator, v))

        let commander = bot(.commander)
        #expect(commander.scoredActions(view: v).first?.action == joined)
        #expect(score(joined, commander, v) - score(apart, commander, v) == 1.5)   // span 0.5 * (9 - 6)
    }

    @Test func spanTermIsZeroWhenFarBehind() {
        // The rival's chain is 20 long and the seat owns F-G (2). G-H would make 4, far short of 20 - 6.
        var s = playing(on: spanMap, cards: [.resource(.red): 2])
        let seat = s.current
        own([0, 1, 2, 3], seat: 1 - seat, in: &s)
        own([4], seat: seat, in: &s)
        let v = view(s, on: spanMap)
        let grow = claim(5, .red, 2)
        let plain = score(grow, bot(.navigator, on: spanMap), v)
        #expect(score(grow, bot(.commander, on: spanMap), v) == plain)

        // Within reach the same claim counts: 4 - max(2, 20 - 17) = 1 at span 0.5.
        var near = BotSettings.level(.commander).weights
        near.spanReach = 17
        #expect(score(grow, bot(.commander, on: spanMap, weights: near), v) == plain + 0.5)
    }

    @Test func closesOutTheGameFromASafeLead() {
        // 5 beacons: claiming B-C (3) leaves 2 and starts the final round, C-D (1) does not.
        var s = playing(cards: [.resource(.blue): 3])
        let seat = s.current
        s.players[seat].beacons = 5
        s.players[seat].score = 30
        s.players[1 - seat].score = 25   // 30 + 4 + the span award 10 leads by 19
        let ending = claim(1, .blue, 3), other = claim(2, .blue, 1)
        let commander = bot(.commander)
        let ahead = (score(ending, commander, view(s)), score(other, commander, view(s)))

        s.players[1 - seat].score = 35   // leads by 9, short of closeOutLead 10
        let close = (score(ending, commander, view(s)), score(other, commander, view(s)))
        #expect(ahead.0 == close.0 + 5)   // closeOut
        #expect(ahead.1 == close.1)

        // An unfulfilled Contract comes off the projected total: 44 - 6 leads 25 by 13, then 6 more off.
        s.players[1 - seat].score = 25
        s.players[seat].contracts = [1]
        #expect(score(ending, commander, view(s)) == score(ending, bot(.navigator), view(s)) + 5 + 1.5)
        s.players[seat].contracts = [1, 3]
        #expect(score(ending, commander, view(s)) == score(ending, bot(.navigator), view(s)) + 1.5)
    }

    @Test func holdsBackFromStartingTheFinalRoundWhenBehind() {
        // 3 beacons and one blue card: C-D (1) is the only claim, and it leaves 2 and starts the final
        // round. The projected total is 30 + 1 + the span award 10 = 41.
        var s = playing(cards: [.resource(.blue): 1])
        let seat = s.current
        s.players[seat].beacons = 3
        s.players[seat].score = 30
        let ending = claim(2, .blue, 1)
        var w = BotSettings.level(.commander).weights
        w.holdBackMargin = 3
        let commander = bot(.commander, weights: w), navigator = bot(.navigator)
        var changed = BotSettings.level(.navigator).weights
        changed.holdBackMargin = 100

        s.players[1 - seat].score = 50   // behind: a draw is within the margin, so the claim waits
        var v = view(s)
        #expect(navigator.scoredActions(view: v).first?.action == ending)
        let behind = commander.scoredActions(view: v)
        #expect(behind.first?.action == .drawBlind || behind.first?.action == .drawExchange(slot: 0))
        #expect(score(ending, commander, v) == behind[0].score - 3)
        let navigatorBehind = navigator.scoredActions(view: v).map(\.score)
        #expect(navigatorBehind == bot(.navigator, weights: changed).scoredActions(view: v).map(\.score))

        s.players[1 - seat].score = 41   // level: not behind, the claim is made
        v = view(s)
        #expect(commander.scoredActions(view: v).first?.action == ending)
        #expect(navigator.scoredActions(view: v).map(\.score) == navigatorBehind)

        // Behind with nothing else within the margin: 5 beacons, B-C (3) ends and leads every other
        // action by more than 3, so it is still made.
        var far = playing(cards: [.resource(.blue): 3])
        far.players[far.current].beacons = 5
        far.players[far.current].score = 30
        far.players[1 - far.current].score = 60
        let top = commander.scoredActions(view: view(far))
        #expect(top[0].action == claim(1, .blue, 3))
        #expect(top[0].score - top[1].score > 3)
        #expect(top[0].score == score(claim(1, .blue, 3), bot(.navigator), view(far)) + 1.5)   // span only
    }

    @Test func neverPicksAnIllegalAction() async {
        // 20 Commander-only games on the standard map: 2 to 5 Houses, hazards off (3 games) and on (2).
        for players in 2...5 {
            for hazards in [false, true] {
                let r = await runMatch(levels: Array(repeating: .commander, count: players),
                                       games: hazards ? 2 : 3, seed: UInt64(players * 100), hazards: hazards)
                #expect(r.illegalMoves == 0, "\(players) Houses, hazards \(hazards)")
                #expect(r.avgTurns > 0)
            }
        }
    }
}
