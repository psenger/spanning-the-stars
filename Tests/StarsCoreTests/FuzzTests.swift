import Testing
@testable import StarsCore

private let allHouses: [House] = [.varn, .solace, .meridian, .ashkar, .paleFleet]

private func checkInvariants(_ s: GameState, map: GalaxyMap, seed: UInt64, step: Int) {
    let ctx = Comment(rawValue: "seed \(seed) step \(step)")
    let cards = s.players.reduce(0) { $0 + $1.hand.total } + s.depot.count
        + s.exchange.compactMap { $0 }.count + s.salvage.count
    #expect(cards == 110, ctx)

    let hazards = s.config.frontierHazards
    for (i, p) in s.players.enumerated() {
        let lanes = p.lanes.map { map.lane($0) }
        #expect(45 - p.beacons == lanes.reduce(0) { $0 + beaconCost($1, hazards: hazards) }, ctx)
        #expect(p.score == lanes.reduce(0) { $0 + lanePoints($1.length) }, ctx)
        #expect(p.lanes.allSatisfy { s.laneOwner[$0] == i }, ctx)
    }
    #expect(s.laneOwner.count == s.players.reduce(0) { $0 + $1.lanes.count }, ctx)

    var contracts = s.contractDeck.count + s.setupReturns.count
        + s.players.reduce(0) { $0 + $1.contracts.count }
    switch s.phase {
    case .setupContracts: contracts += s.pendingOffers[s.current...].reduce(0) { $0 + $1.count }
    case let .choosingContracts(offered): contracts += offered.count
    default: break
    }
    #expect(contracts == map.contracts.count, ctx)
}

@Suite struct FuzzTests {
    @Test func randomGamesStayConsistent() throws {
        let engine = GameEngine(map: .standard)
        for seed in UInt64(1)...500 {
            let houses = Array(allHouses.prefix(2 + Int(seed % 4)))
            var state = engine.newGame(GameConfig(houses: houses, frontierHazards: seed.isMultiple(of: 2), seed: seed))
            var picker = SeededRNG(seed: seed)
            var steps = 0
            while state.phase != .gameOver, steps < 3000 {
                let actions = engine.legalActions(state)
                try #require(!actions.isEmpty, "no legal actions, seed \(seed) step \(steps)")
                let action = actions.randomElement(using: &picker)!
                do {
                    _ = try engine.apply(action, to: &state)
                } catch {
                    Issue.record("seed \(seed) step \(steps): \(action) threw \(error)")
                    return
                }
                steps += 1
                checkInvariants(state, map: .standard, seed: seed, step: steps)
            }
            try #require(state.phase == .gameOver, "seed \(seed) did not finish in 3000 actions")
            #expect(engine.legalActions(state).isEmpty)

            for f in finalScores(state, map: .standard) {
                let bonus = f.spanBonus
                #expect(f.total == f.lanePoints + f.contractsGained - f.contractsLost + bonus)
                #expect(f.lanePoints == state.players[f.player].score)
            }
        }
    }
}
