import Testing
@testable import StarsCore

private let red = Card.resource(.red)
private let blue = Card.resource(.blue)
private let green = Card.resource(.green)
private let orange = Card.resource(.orange)

private func game(hazards: Bool = true, hand: [Card: Int] = [:]) -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    var s = e.newGame(GameConfig(houses: [.varn, .solace, .meridian], frontierHazards: hazards, seed: 3))
    s.phase = .awaitingAction
    s.current = 0
    for i in s.players.indices { s.players[i].hand = Hand() }
    for (c, n) in hand { s.players[0].hand.add(c, n) }
    return (e, s)
}

private func claims(_ e: GameEngine, _ s: GameState, lane: Int) -> [Payment] {
    e.legalActions(s).compactMap {
        if case let .claim(id, p) = $0, id == lane { p } else { nil }
    }
}

@Suite struct HazardTests {
    @Test func spectrumNeedsDistinctColors() {
        let (e, s) = game(hand: [red: 2, blue: 1, green: 1])
        let offered = claims(e, s, lane: 4)
        #expect(offered.contains(Payment([red: 1, blue: 1, green: 1])))
        #expect(!offered.contains(Payment([red: 2, blue: 1])))
    }

    @Test func spectrumCoresFillGaps() {
        let (e, s) = game(hand: [red: 1, .core: 2])
        #expect(claims(e, s, lane: 4).contains(Payment([red: 1, .core: 2])))
    }

    @Test func gravityCostsOneFewerCard() {
        let (e, s) = game(hand: [orange: 3])
        let offered = claims(e, s, lane: 5)
        #expect(offered.contains(Payment([orange: 2])))
        #expect(!offered.contains(Payment([orange: 3])))
    }

    @Test func gravitySpendsExtraBeacon() throws {
        var (e, s) = game(hand: [orange: 2])
        _ = try e.apply(.claim(laneID: 5, payment: Payment([orange: 2])), to: &s)
        #expect(s.players[0].beacons == 41)
        #expect(s.players[0].score == 4)
        #expect(s.players[0].lanes == [5])
    }

    @Test func gravityNeedsLengthPlusOneBeacons() {
        var (e, s) = game(hand: [orange: 3])
        s.players[0].beacons = 3
        #expect(claims(e, s, lane: 5).isEmpty)
        #expect(throws: RuleError.notEnoughBeacons) {
            try e.apply(.claim(laneID: 5, payment: Payment([orange: 2])), to: &s)
        }
    }

    @Test func hazardsOffArePlainLanes() throws {
        var (e, s) = game(hazards: false, hand: [.resource(.purple): 3, orange: 3])
        #expect(claims(e, s, lane: 4) == [Payment([.resource(.purple): 3])])
        #expect(claims(e, s, lane: 5) == [Payment([orange: 3])])
        _ = try e.apply(.claim(laneID: 5, payment: Payment([orange: 3])), to: &s)
        #expect(s.players[0].beacons == 42)
    }
}
