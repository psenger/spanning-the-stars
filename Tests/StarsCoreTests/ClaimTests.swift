import Testing
@testable import StarsCore

private let red = Card.resource(.red)
private let blue = Card.resource(.blue)
private let green = Card.resource(.green)

private func game(houses: [House] = [.varn, .solace, .meridian], hand: [Card: Int] = [:]) -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    var s = e.newGame(GameConfig(houses: houses, frontierHazards: false, seed: 3))
    s.phase = .awaitingAction
    s.current = 0
    for i in s.players.indices { s.players[i].hand = Hand() }
    for (c, n) in hand { s.players[0].hand.add(c, n) }
    return (e, s)
}

@Suite struct ClaimTests {
    @Test func claimAppendsToPublicLog() throws {
        var (e, s) = game(hand: [red: 2])
        let before = s.log.count
        _ = try e.apply(.claim(laneID: 0, payment: Payment([red: 2])), to: &s)
        #expect(s.log.count == before + 1)
        #expect(s.log.last == .claimed(player: 0, laneID: 0, points: 2))
    }

    @Test func redLaneWithTwoReds() throws {
        var (e, s) = game(hand: [red: 2])
        let salvageBefore = s.salvage.count
        let events = try e.apply(.claim(laneID: 0, payment: Payment([red: 2])), to: &s)
        #expect(s.players[0].score == 2)
        #expect(s.players[0].beacons == 43)
        #expect(s.salvage.count == salvageBefore + 2)
        #expect(s.laneOwner[0] == 0)
        #expect(s.players[0].lanes == [0])
        #expect(s.players[0].hand.total == 0)
        #expect(events.contains(.claimed(player: 0, laneID: 0, points: 2)))
        #expect(s.current == 1)
    }

    @Test func coresSubstitute() throws {
        var (e, s) = game(hand: [red: 1, .core: 1])
        _ = try e.apply(.claim(laneID: 0, payment: Payment([red: 1, .core: 1])), to: &s)
        #expect(s.laneOwner[0] == 0)
    }

    @Test func openLaneAcceptsAnyOneColor() throws {
        var (e, s) = game(hand: [blue: 3, green: 3])
        #expect(throws: RuleError.invalidPayment) {
            try e.apply(.claim(laneID: 1, payment: Payment([blue: 2, green: 1])), to: &s)
        }
        _ = try e.apply(.claim(laneID: 1, payment: Payment([blue: 3])), to: &s)
        #expect(s.players[0].score == 4)
    }

    @Test func pointsTable() {
        #expect((1...6).map(lanePoints) == [1, 2, 4, 7, 10, 15])
    }

    @Test func cannotClaimTaken() {
        var (e, s) = game(hand: [red: 2])
        s.laneOwner[0] = 1
        #expect(throws: RuleError.laneTaken) {
            try e.apply(.claim(laneID: 0, payment: Payment([red: 2])), to: &s)
        }
    }

    @Test func twinClosedWithThreePlayers() {
        var (e, s) = game(hand: [blue: 1, green: 1])
        s.laneOwner[2] = 1
        #expect(throws: RuleError.laneClosed) {
            try e.apply(.claim(laneID: 3, payment: Payment([green: 1])), to: &s)
        }
    }

    @Test func twinOpenWithFourPlayersButNotSameHouse() throws {
        var (e, s) = game(houses: [.varn, .solace, .meridian, .ashkar], hand: [blue: 1, green: 1])
        s.laneOwner[2] = 1
        s.players[1].lanes = [2]
        _ = try e.apply(.claim(laneID: 3, payment: Payment([green: 1])), to: &s)
        #expect(s.laneOwner[3] == 0)

        var (e2, s2) = game(houses: [.varn, .solace, .meridian, .ashkar], hand: [blue: 1, green: 1])
        s2.laneOwner[2] = 0
        s2.players[0].lanes = [2]
        #expect(throws: RuleError.ownsTwin) {
            try e2.apply(.claim(laneID: 3, payment: Payment([green: 1])), to: &s2)
        }
    }

    @Test func notEnoughBeacons() {
        var (e, s) = game(hand: [blue: 3])
        s.players[0].beacons = 2
        #expect(throws: RuleError.notEnoughBeacons) {
            try e.apply(.claim(laneID: 1, payment: Payment([blue: 3])), to: &s)
        }
    }

    @Test func optionsDeduped() {
        var hand = Hand()
        hand.add(.core, 3)
        hand.add(red, 2)
        let open = Lane(id: 9, a: "A", b: "B", length: 2, color: .open, hazard: .none, twinID: nil)
        let opts = paymentOptions(for: open, hand: hand, hazards: false)
        #expect(Set(opts).count == opts.count)
        #expect(opts.filter { $0.counts == [.core: 2] }.count == 1)
        #expect(opts.count == 3)  // 2 red, 1 red + 1 core, 2 core
        #expect(opts.map(\.total).allSatisfy { $0 == 2 })
    }

    @Test func legalActionsListClaims() {
        let (e, s) = game(hand: [red: 2, .core: 1])
        let claims = e.legalActions(s).filter { if case .claim = $0 { true } else { false } }
        #expect(claims.contains(.claim(laneID: 0, payment: Payment([red: 2]))))
        #expect(claims.contains(.claim(laneID: 0, payment: Payment([red: 1, .core: 1]))))
        #expect(!claims.contains(.claim(laneID: 6, payment: Payment([red: 2]))))
    }

    @Test func beaconCostRule() {
        let t = GalaxyMap.tiny
        #expect(beaconCost(t.lane(5), hazards: true) == 4)
        #expect(beaconCost(t.lane(5), hazards: false) == 3)
        #expect(beaconCost(t.lane(0), hazards: true) == 2)
    }
}
