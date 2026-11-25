import Testing
@testable import StarsCore

private let standard = GameEngine(map: .standard)

/// The tiny map with its four Contracts listed twice, so a 2-seat setup has enough to offer.
/// Ids 0 to 3 are A-C (5), A-D (6), B-F (7), A-E (6); ids 4 to 7 repeat them.
private let tinyMap: GalaxyMap = {
    let t = GalaxyMap.tiny
    let pairs = [("A", "C"), ("A", "D"), ("B", "F"), ("A", "E")]
    return GalaxyMap(systems: t.systems, lanes: t.lanes,
                     contractPairs: (pairs + pairs).map { (a: $0.0, b: $0.1, flavor: "t") })
}()
private let tiny = GameEngine(map: tinyMap)

/// Seat 0's view of a 2-House game where seat 0 holds `contracts` and `owners` maps lane to seat.
private func view(_ engine: GameEngine, contracts: [Int] = [], owners: [Int: Int]) -> PlayerView {
    var s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 7))
    s.players[0].contracts = contracts
    s.laneOwner = owners
    for seat in s.players.indices {
        s.players[seat].lanes = owners.filter { $0.value == seat }.keys.sorted()
    }
    return PlayerView(state: s, seat: 0, engine: engine)
}

@Suite struct OpponentModelTests {
    @Test func ranksTheTrueGoalInTheTopThree() {
        let graph = MapGraph(map: .standard)
        let model = OpponentModel(graph: graph)
        // Contract 27 is a single lane, so "every lane but the last" shows nothing; 30 stands in for it.
        var tested = 0
        for id in stride(from: 0, through: 30, by: 3) {
            let c = graph.map.contracts[id]
            let route = graph.route(from: c.a, to: c.b, seat: 1, laneOwner: [:], playerCount: 2)!
            let owned = route.toClaim.dropLast()
            if owned.isEmpty { continue }
            tested += 1
            let v = view(standard, owners: Dictionary(uniqueKeysWithValues: owned.map { ($0, 1) }))
            let top = model.likelyContracts(of: 1, view: v).prefix(3).map(\.contractID)
            #expect(top.contains(id), "contract \(id) \(c.a)-\(c.b), top three \(top)")
        }
        #expect(tested == 10)
    }

    @Test func likelihoodsSumToOneAndExcludeMyContracts() {
        let v = view(standard, contracts: [0, 5, 9], owners: [0: 1, 1: 1, 2: 1, 3: 0])
        let guesses = OpponentModel(graph: MapGraph(map: .standard)).likelyContracts(of: 1, view: v)
        #expect(abs(guesses.map(\.likelihood).reduce(0, +) - 1) < 1e-9)
        #expect(guesses.count == 30)
        #expect(Set(guesses.map(\.contractID)).isDisjoint(with: [0, 5, 9]))
        #expect(guesses.allSatisfy { $0.likelihood > 0 })
        #expect(guesses.map(\.likelihood) == guesses.map(\.likelihood).sorted(by: >))
    }

    @Test func noLanesMeansAFlatGuess() {
        // The viewer's own lanes only lengthen the rival's routes, which is not progress.
        let v = view(standard, owners: [0: 0, 1: 0, 2: 0])
        let guesses = OpponentModel(graph: MapGraph(map: .standard)).likelyContracts(of: 1, view: v)
        #expect(guesses.count == 33)
        #expect(guesses.allSatisfy { $0.likelihood == guesses[0].likelihood })
        #expect(guesses.map(\.contractID) == Array(0..<33))
    }

    @Test func blockValueIsPositiveOnTheRivalsCriticalLane() {
        // The rival owns A-B, so A-C and A-D run through B-C. A-F only shortens B-F, an unlikely goal.
        let v = view(tiny, owners: [0: 1])
        let model = OpponentModel(graph: MapGraph(map: tinyMap))
        let critical = model.blockValue(laneID: 1, view: v)
        let side = model.blockValue(laneID: 6, view: v)
        #expect(critical > 1)
        #expect(critical > side)
        #expect(side >= 0 && side < 0.25)
    }

    @Test func blockValueIsZeroForTakenLanes() {
        let model = OpponentModel(graph: MapGraph(map: tinyMap))
        // B-C is critical to the rival while free, and worth nothing once either seat owns it.
        #expect(model.blockValue(laneID: 1, view: view(tiny, owners: [0: 1, 1: 1])) == 0)
        #expect(model.blockValue(laneID: 1, view: view(tiny, owners: [0: 1, 1: 0])) == 0)
        #expect(model.blockValue(laneID: 0, view: view(tiny, owners: [0: 1])) == 0)
    }
}
