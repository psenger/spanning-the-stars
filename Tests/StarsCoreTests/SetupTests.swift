import Testing
@testable import StarsCore

private func newState(houses: [House] = [.varn, .solace, .meridian]) -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    return (e, e.newGame(GameConfig(houses: houses, frontierHazards: false, seed: 7)))
}

@Suite struct SetupTests {
    @Test func setupDealsFourCardsAndFourOffers() {
        let (e, s) = newState()
        #expect(s.players.allSatisfy { $0.hand.total == 4 })
        #expect(s.pendingOffers.count == 3)
        #expect(s.pendingOffers.allSatisfy { $0.count == 4 })
        #expect(s.phase == .setupContracts(offered: s.pendingOffers[0]))
        #expect(s.current == 0)
        #expect(s.contractDeck.count == e.map.contracts.count - 12)
    }

    @Test func setupCardConservation() {
        let (_, s) = newState()
        let hands = s.players.reduce(0) { $0 + $1.hand.total }
        #expect(hands + s.depot.count + s.exchange.compactMap { $0 }.count + s.salvage.count == 110)
        #expect(s.exchange.count == 5)
    }

    @Test func exchangeResetsOnThreeCores() {
        var (_, s) = newState()
        s.exchange = [.core, .core, .core, .resource(.red), .resource(.blue)]
        s.depot = Array(repeating: .resource(.red), count: 10)
        s.salvage = []
        let events = refillExchange(&s)
        #expect(s.exchange.compactMap { $0 }.filter { $0 == .core }.count < 3)
        #expect(s.salvage.count == 5)
        #expect(events.contains(.exchangeReset))
    }

    @Test func exchangeResetStopsWhenImpossible() {
        var (_, s) = newState()
        s.exchange = Array(repeating: Card.core, count: 5)
        s.depot = []
        s.salvage = []
        let events = refillExchange(&s)
        #expect(s.exchange == Array(repeating: Card.core, count: 5))
        #expect(!events.contains(.exchangeReset))
    }

    @Test func drawFromDepotReshufflesSalvage() {
        var (_, s) = newState()
        s.depot = []
        s.salvage = [.core, .resource(.red)]
        #expect(drawFromDepot(&s) != nil)
        #expect(s.salvage.isEmpty)
        #expect(s.depot.count == 1)
    }

    @Test func beaconsStartAt45() {
        let (_, s) = newState()
        #expect(s.players.allSatisfy { $0.beacons == 45 })
    }

    @Test func scoresStartAt0() {
        let (_, s) = newState()
        #expect(s.players.allSatisfy { $0.score == 0 })
    }
}
