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

/// A-B is a twin pair of length 1 (lanes 3 and 4) whose only bypass is the long A-C lane;
/// B-C (lane 0, length 1) has the short bypass B-D-C. Every Contract is A-C (2).
private let twinMap: GalaxyMap = {
    let systems = ["A", "B", "C", "D"].enumerated().map { i, n in
        StarSystem(id: n, name: n, region: .coreWorlds, x: Double(i), y: 0)
    }
    func lane(_ id: Int, _ a: String, _ b: String, _ len: Int, _ color: ResourceColor, twin: Int? = nil) -> Lane {
        Lane(id: id, a: a, b: b, length: len, color: .color(color), hazard: .none, twinID: twin)
    }
    let lanes = [
        lane(0, "B", "C", 1, .red),
        lane(1, "B", "D", 1, .yellow),
        lane(2, "D", "C", 1, .orange),
        lane(3, "A", "B", 1, .blue, twin: 4),
        lane(4, "A", "B", 1, .green, twin: 3),
        lane(5, "A", "C", 6, .white),
    ]
    return GalaxyMap(systems: systems, lanes: lanes,
                     contractPairs: (0..<8).map { _ in (a: "A", b: "C", flavor: "t") })
}()

/// Setup done; the current seat holds exactly `contracts` and `cards`.
private func playing(on map: GalaxyMap = map, contracts: [Int], cards: [Card: Int]) -> GameState {
    let engine = GameEngine(map: map)
    var s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 7,
                                      kinds: [.bot(.navigator), .bot(.navigator)]))
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

private func navigator(on map: GalaxyMap = map, weights: BotWeights? = nil) -> HeuristicBot {
    var settings = BotSettings.level(.navigator)
    settings.temperature = 0
    settings.mistakeRate = 0
    if let weights { settings.weights = weights }
    return HeuristicBot(settings: settings, map: map)
}

private func view(_ s: GameState, on map: GalaxyMap = map) -> PlayerView {
    PlayerView(state: s, seat: s.current, engine: GameEngine(map: map))
}

private func black(_ lane: Int, _ n: Int) -> Action {
    .claim(laneID: lane, payment: Payment([.resource(.black): n]))
}

@Suite struct NavigatorTests {
    @Test func navigatorSettingsUseThePlannerAndTheScorer() {
        let s = BotSettings.level(.navigator)
        #expect(s.usesPlanner && s.usesScorer && !s.usesOpponentModel && s.playouts == 0)
        #expect(s.temperature > 0 && s.temperature < BotSettings.level(.pilot).temperature)
        #expect(s.mistakeRate > 0 && s.mistakeRate < BotSettings.level(.pilot).mistakeRate)
        let w = BotWeights()
        #expect(w.planProgress == 1.5 && w.urgency == 0.5 && w.coreValue == 4 && w.claimNowBonus == 2)
        #expect(w.contractBeaconFloor == 15 && w.endgameBeacons == 8 && w.endgamePointsBoost == 1.5)
        #expect(s.weights.keepCostWeight == 1.2)   // tuned, see docs/ai-results.md
        #expect(BotRoster(engine: GameEngine(map: map)).bot(.navigator) is HeuristicBot)
    }

    @Test func keepsOnlyTheContractsThatShareItsPlan() {
        // At setup no Contract is worth its whole route (value - 1.2 * cost is below 0): the two
        // cheapest losses are kept, A-C (-1) and A-D (-1.2).
        var s = playing(contracts: [], cards: [:])
        s.phase = .setupContracts(offered: [0, 1, 2, 3])
        #expect(navigator().scoredActions(view: view(s)).first?.action == .keepContracts([0, 1]))

        // Holding A-D, A-C rides on its lanes for nothing and A-E needs only D-E; B-F shares nothing.
        s.players[s.current].contracts = [1]
        s.phase = .choosingContracts(offered: [0, 2, 3])
        #expect(navigator().scoredActions(view: view(s)).first?.action == .keepContracts([0, 3]))
    }

    @Test func aForgottenContractDoesNotCountAsDone() {
        // The mistake drops the only goal; the Contract is still open, so no new ones are drawn.
        var settings = BotSettings.level(.navigator)
        settings.temperature = 0
        settings.mistakeRate = 1
        let s = playing(contracts: [1], cards: [:])
        var rng = SeededRNG(seed: 1)
        let choice = HeuristicBot(settings: settings, map: map).chooseAction(view: view(s), rng: &rng, deadline: nil)
        #expect(choice != .drawContracts)
        #expect(view(s).legalActions.contains(.drawContracts))
    }

    @Test func replansAfterABlock() {
        // Contract A-D. Its route is A-B, B-C, C-D until the rival claims B-C; then it goes round by B-E.
        var s = playing(contracts: [1], cards: [.resource(.black): 4])
        #expect(navigator().goals(view: view(s)) == [Goal(contractID: 1, value: 6, route: Route(toClaim: [0, 1, 2], cost: 6))])
        own([1], seat: 1 - s.current, in: &s)
        #expect(navigator().goals(view: view(s)) == [Goal(contractID: 1, value: 6, route: Route(toClaim: [0, 7, 4], cost: 9))])
        let scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == black(7, 4))
        // 7 points + planProgress 1.5 * 6 * 4 / 9 + urgency 0.5 * 3 (losing B-E leaves A-F, F-E, E-D)
        #expect(abs((scored.first?.score ?? 0) - 12.5) < 1e-9)
    }

    @Test func abandonsAnImpossibleContract() {
        // The rival owns A-B and A-F, so A is cut off and Contract A-D has no route.
        var s = playing(contracts: [1], cards: [:])
        s.exchange = [.resource(.red), .resource(.blue), .resource(.green), .resource(.purple), .core]
        let wantedRed = navigator().scoredActions(view: view(s)).first { $0.action == .drawExchange(slot: 0) }
        #expect(wantedRed?.score == 2.5)   // before the block: draw 1 + cardNeed 3 * 1/2

        own([0, 6], seat: 1 - s.current, in: &s)
        #expect(navigator().goals(view: view(s)) == [Goal(contractID: 1, value: 6, route: nil)])
        let scored = navigator().scoredActions(view: view(s))
        for slot in 0..<5 {
            #expect(scored.first { $0.action == .drawExchange(slot: slot) }?.score == 1, "slot \(slot)")
        }
        // Nothing is left to work for, so it looks for new Contracts.
        #expect(scored.first?.action == .drawContracts)
    }

    @Test func sharesLanesBetweenContracts() {
        // A-D (6) is planned first; A-C (5) then rides on its lanes for nothing.
        let s = playing(contracts: [0, 1], cards: [:])
        let goals = navigator().goals(view: view(s))
        #expect(goals == [Goal(contractID: 0, value: 5, route: Route(toClaim: [0, 1], cost: 0)),
                          Goal(contractID: 1, value: 6, route: Route(toClaim: [0, 1, 2], cost: 6))])
        #expect(Set(goals.flatMap { $0.route?.toClaim ?? [] }).sorted() == [0, 1, 2])
        #expect(goals.reduce(0) { $0 + ($1.route?.cost ?? 0) } == 6)   // not 5 + 6
    }

    @Test func urgentShortLaneBeatsALongerOne() {
        // Contract A-C by A-B (blue twin, lane 3) and B-C (red, lane 0): both length 1, both payable.
        // Losing A-B closes its twin and leaves the 6-long A-C lane; losing B-C costs one lane more.
        let s = playing(on: twinMap, contracts: [0], cards: [.resource(.blue): 1, .resource(.red): 1])
        let v = view(s, on: twinMap)
        #expect(navigator(on: twinMap).goals(view: v) == [Goal(contractID: 0, value: 2, route: Route(toClaim: [3, 0], cost: 2))])
        let twin = Action.claim(laneID: 3, payment: Payment([.resource(.blue): 1]))
        let plain = Action.claim(laneID: 0, payment: Payment([.resource(.red): 1]))
        let scored = navigator(on: twinMap).scoredActions(view: v)
        #expect(scored.first?.action == twin)
        #expect(scored.first?.score == 4.5)   // 1 point + planProgress 1.5 * 2 * 1/2 + urgency 0.5 * 4
        #expect(scored.first { $0.action == plain }!.score < 4.5)

        // Without urgency the two tie and the lower lane id comes first.
        var calm = BotWeights()
        calm.urgency = 0
        let even = navigator(on: twinMap, weights: calm).scoredActions(view: v)
        #expect(even.first?.action == plain)
        #expect(even.first?.score == even.first { $0.action == twin }?.score)
    }

    @Test func aTwinOfAWantedLaneIsWanted() {
        // The route names the blue twin; the hand pays for the green one, which joins the same systems.
        var s = playing(on: twinMap, contracts: [0], cards: [.resource(.green): 1])
        s.exchange = [.resource(.blue), .resource(.green), .resource(.white), .resource(.yellow), .resource(.white)]
        let green = Action.claim(laneID: 4, payment: Payment([.resource(.green): 1]))
        #expect(navigator(on: twinMap).scoredActions(view: view(s, on: twinMap)).first?.action == green)
        // The same progress and urgency as the blue twin: 1 + 1.5 + 2.
        #expect(navigator(on: twinMap).scoredActions(view: view(s, on: twinMap)).first?.score == 4.5)

        s.exchange[2] = .resource(.red)
        let scored = navigator(on: twinMap).scoredActions(view: view(s, on: twinMap))
        // A-B is paid by either twin, so blue is not needed; B-C still wants red.
        #expect(scored.first { $0.action == .drawExchange(slot: 0) }?.score == 1)
        #expect(scored.first { $0.action == .drawExchange(slot: 2) }?.score == 4)   // draw 1 + cardNeed 3

        // With neither twin paid, either color helps.
        s.players[s.current].hand = Hand()
        let empty = navigator(on: twinMap).scoredActions(view: view(s, on: twinMap))
        #expect(empty.first { $0.action == .drawExchange(slot: 0) }?.score == 4)
        #expect(empty.first { $0.action == .drawExchange(slot: 1) }?.score == 4)
    }

    @Test func paymentsArePenalizedByTheirCores() {
        // B-C is open: every color pays, and only the Cores in a payment cost anything.
        let s = playing(contracts: [0], cards: [.resource(.red): 3, .resource(.yellow): 3, .core: 1])
        let scored = navigator().scoredActions(view: view(s))
        func score(_ payment: [Card: Int]) -> Double? {
            scored.first { $0.action == .claim(laneID: 1, payment: Payment(payment)) }?.score
        }
        #expect(score([.resource(.red): 3]) == score([.resource(.yellow): 3]))
        #expect(score([.resource(.red): 2, .core: 1]) == score([.resource(.yellow): 2, .core: 1]))
        #expect(score([.resource(.red): 3])! > score([.resource(.red): 2, .core: 1])!)
    }

    @Test func takesAFaceUpCoreWhileALaneIsUnpaid() {
        var s = playing(contracts: [0], cards: [:])
        s.exchange = [.resource(.blue), .core, .resource(.green), .resource(.yellow), .resource(.purple)]
        let scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == .drawExchange(slot: 1))
        #expect(scored.first?.score == 4)   // coreValue
    }

    @Test func aPayableWantedLaneOutranksEveryDraw() {
        // C-D (length 1) is the last lane of a long route: little progress, yet it beats the best draw.
        var s = playing(contracts: [1], cards: [.resource(.blue): 1])
        s.exchange = [.resource(.red), .core, .resource(.green), .resource(.yellow), .resource(.purple)]
        let scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == .claim(laneID: 2, payment: Payment([.resource(.blue): 1])))
        #expect(scored.first?.score == 6)   // best draw (the Core, 4) + claimNowBonus 2
    }

    @Test func aWantedLanePayableOnlyWithCoresOutranksEveryDraw() {
        // C-D and its twin are payable with the one Core alone. The Core does not eat the lead.
        var s = playing(contracts: [1], cards: [.core: 1])
        s.exchange = [.resource(.red), .core, .resource(.green), .resource(.yellow), .resource(.purple)]
        var scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == .claim(laneID: 2, payment: Payment([.core: 1])))
        #expect(scored.first?.score == 6)   // best draw (the Core, 4) + claimNowBonus 2
        #expect(scored.first { $0.action == .drawExchange(slot: 1) }?.score == 4)

        // With a blue card too, the Core-free payment has the lead and the Core payment sits 1 below it.
        s.players[s.current].hand.add(.resource(.blue))
        scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == .claim(laneID: 2, payment: Payment([.resource(.blue): 1])))
        #expect(scored.first?.score == 6)
        #expect(scored.first { $0.action == .claim(laneID: 2, payment: Payment([.core: 1])) }?.score == 5)
    }

    @Test func aBlindDrawHasNoCardNeedWhenNothingIsWanted() {
        // Contract A-D is open: a blind draw has its share of cardNeed (draw 1 + 3 * 0.3).
        var s = playing(contracts: [1], cards: [:])
        #expect(navigator().scoredActions(view: view(s)).first { $0.action == .drawBlind }?.score == 1.9)

        // Abandoned (the rival owns A-B and A-F): no card is needed, seen or unseen.
        own([0, 6], seat: 1 - s.current, in: &s)
        #expect(navigator().scoredActions(view: view(s)).first { $0.action == .drawBlind }?.score == 1)
        // Pilot keeps its share.
        let pilot = HeuristicBot(settings: .level(.pilot), map: map)
        #expect(pilot.scoredActions(view: view(s)).first { $0.action == .drawBlind }?.score == 1.9)

        // Fulfilled (the seat owns A-B and B-C for Contract A-C): the same.
        var done = playing(contracts: [0], cards: [:])
        own([0, 1], seat: done.current, in: &done)
        #expect(navigator().scoredActions(view: view(done)).first { $0.action == .drawBlind }?.score == 1)
    }

    @Test func endgameModeTakesPoints() {
        // Contract A-C wants A-B and B-C. The hand pays for both and for B-E (7 points), which is off plan.
        var s = playing(contracts: [0], cards: [.resource(.black): 4, .resource(.red): 2])
        let seat = s.current
        #expect(navigator().scoredActions(view: view(s)).first?.action == black(1, 3))

        s.players[1 - seat].beacons = 5
        var scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == black(7, 4))
        #expect(scored.first?.score == 10.5)   // 7 points * endgamePointsBoost 1.5
        #expect(scored.first { $0.action == black(1, 3) }?.score == 6)   // 4 * 1.5, no plan progress
        #expect(scored.first { $0.action == .drawBlind }?.score == 1)
        #expect(scored.last?.action == .drawContracts)
        #expect(scored.last?.score == -100)

        // A claim that completes a Contract this turn keeps its plan progress.
        own([0], seat: seat, in: &s)
        scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action == black(1, 3))
        #expect(scored.first?.score == 13.5)   // 4 * 1.5 + planProgress 1.5 * 5

        // The final round is endgame mode too.
        s.players[1 - seat].beacons = 45
        s.finalTurnsRemaining = 2
        #expect(navigator().scoredActions(view: view(s)).last?.score == -100)
    }

    @Test func drawsContractsOnlyWhenGoalsAreDone() {
        // The seat owns A-B and B-C: Contract A-C is fulfilled.
        var s = playing(contracts: [0], cards: [:])
        let seat = s.current
        own([0, 1], seat: seat, in: &s)
        s.players[seat].beacons = 30
        #expect(navigator().scoredActions(view: view(s)).first?.action == .drawContracts)

        // Too few beacons to start on new Contracts.
        s.players[seat].beacons = 14
        #expect(navigator().scoredActions(view: view(s)).first { $0.action == .drawContracts }?.score == -2)

        // Contract A-D is still open.
        s.players[seat].beacons = 30
        s.players[seat].contracts = [0, 1]
        let scored = navigator().scoredActions(view: view(s))
        #expect(scored.first?.action != .drawContracts)
        #expect(scored.first { $0.action == .drawContracts }?.score == -2)
    }

    @Test func neverPicksAnIllegalAction() async {
        // 60 Navigator-only games on the standard map: 2 to 5 Houses, hazards off (8 games) and on (7).
        for players in 2...5 {
            for hazards in [false, true] {
                let r = await runMatch(levels: Array(repeating: .navigator, count: players),
                                       games: hazards ? 7 : 8, seed: UInt64(players * 100), hazards: hazards)
                #expect(r.illegalMoves == 0, "\(players) Houses, hazards \(hazards)")
                #expect(r.avgTurns > 0)
            }
        }
    }
}
