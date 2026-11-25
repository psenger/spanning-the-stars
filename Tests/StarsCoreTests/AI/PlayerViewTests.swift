import Testing
@testable import StarsCore

private let engine = GameEngine(map: .standard)

/// A new game with setup done: each seat keeps its first 2 offered Contracts.
private func playing(seed: UInt64, houses: [House], hazards: Bool = false) -> GameState {
    var s = engine.newGame(GameConfig(houses: houses, frontierHazards: hazards, seed: seed))
    while case let .setupContracts(offered) = s.phase {
        _ = try! engine.apply(.keepContracts(Array(offered.prefix(2))), to: &s)
    }
    return s
}

@Suite struct PlayerViewTests {
    @Test func viewShowsOwnSecretsAndPublicCounts() {
        let s = playing(seed: 7, houses: [.varn, .solace, .meridian])
        let v = PlayerView(state: s, seat: s.current, engine: engine)
        #expect(v.hand == s.players[s.current].hand)
        #expect(v.contracts == s.players[s.current].contracts)
        #expect(v.seats.map(\.handCount) == s.players.map(\.hand.total))
        #expect(v.seats.map(\.contractCount) == s.players.map(\.contracts.count))
        #expect(v.depotCount == s.depot.count && v.salvageCount == s.salvage.count)
        #expect(v.contractDeckCount == s.contractDeck.count)
        #expect(v.exchange == s.exchange && v.laneOwner == s.laneOwner)
        #expect(v.legalActions == engine.legalActions(s))
    }

    @Test func viewIsBlindToHiddenState() {
        // Two true states that differ only in what seat 0 cannot see give equal views.
        let a = playing(seed: 7, houses: [.varn, .solace])
        var b = a
        let seat = a.current, other = 1 - seat
        b.depot.reverse()
        b.contractDeck.reverse()
        b.rng = SeededRNG(seed: 999)
        b.config.seed = 12345
        // swap the rival's hand with the same number of depot cards
        let n = b.players[other].hand.total
        var newHand = Hand()
        for _ in 0..<n { newHand.add(b.depot.removeLast()) }
        for (card, count) in b.players[other].hand.counts { b.depot += Array(repeating: card, count: count) }
        b.players[other].hand = newHand
        b.players[other].contracts = Array(b.contractDeck.suffix(b.players[other].contracts.count))
        // the hidden parts really differ, so equal views mean the view does not carry them
        #expect(a.players[other].hand != b.players[other].hand)
        #expect(a.players[other].contracts != b.players[other].contracts)
        #expect(a.depot != b.depot && a.contractDeck != b.contractDeck)
        #expect(PlayerView(state: a, seat: seat, engine: engine) == PlayerView(state: b, seat: seat, engine: engine))
    }

    @Test func nonCurrentSeatSeesNoOffersOrActions() {
        let s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 3))
        let v = PlayerView(state: s, seat: 1, engine: engine)   // seat 0 is choosing
        #expect(v.phase == .setupContracts(offered: []))
        #expect(v.legalActions.isEmpty)
    }

    @Test func viewClaimBlockerMatchesEngine() throws {
        var s = playing(seed: 11, houses: [.varn, .solace, .meridian, .ashkar], hazards: true)
        var rng = SeededRNG(seed: 11)
        var checked = 0, blocked = 0
        func check() {
            let v = PlayerView(state: s, seat: 0, engine: engine)
            for lane in engine.map.lanes {
                for seat in s.players.indices {
                    let expected = engine.claimBlocker(lane, seat: seat, in: s)
                    #expect(v.claimBlocker(lane, seat: seat) == expected)
                    checked += 1
                    if expected != nil { blocked += 1 }
                }
            }
        }
        check()
        for _ in 0..<200 {
            guard let action = engine.legalActions(s).randomElement(using: &rng) else { break }
            _ = try engine.apply(action, to: &s)
            check()
        }
        #expect(checked > 0 && blocked > 0)
    }
}
