import Testing
@testable import StarsCore

private func lane(_ id: Int, _ a: String, _ b: String, _ len: Int) -> Lane {
    Lane(id: id, a: a, b: b, length: len, color: .open, hazard: .none, twinID: nil)
}

private func contract(_ a: String, _ b: String, value: Int = 5) -> Contract {
    Contract(id: 0, a: a, b: b, value: value, flavor: "t")
}

/// Tiny lanes: 0 A-B 2, 1 B-C 3, 2/3 C-D 1, 4 D-E 3, 5 E-F 3, 6 A-F 6, 7 B-E 4.
/// Contracts: 0 A-C, 1 A-D, 2 B-F, 3 A-E, remaining all A-C.
private func scoringSetup(houses: Int = 2) -> (GalaxyMap, GameState) {
    let t = GalaxyMap.tiny
    var pairs: [(a: String, b: String, flavor: String)] = t.contracts.map { ($0.a, $0.b, $0.flavor) }
    pairs += (0..<16).map { _ in (a: "A", b: "C", flavor: "t") }
    let map = GalaxyMap(systems: t.systems, lanes: t.lanes, contractPairs: pairs)
    let hs = Array([House.varn, .solace, .meridian].prefix(houses))
    let s = GameEngine(map: map).newGame(GameConfig(houses: hs, frontierHazards: false, seed: 1))
    return (map, s)
}

private func give(_ s: inout GameState, _ player: Int, lanes: [Int], contracts: [Int]) {
    s.players[player].lanes = lanes
    for l in lanes { s.laneOwner[l] = player }
    s.players[player].contracts = contracts
}

@Suite struct ScoringTests {
    @Test func contractCompleteOnlyWithOwnLanes() {
        let mine = [lane(0, "A", "B", 2), lane(1, "B", "C", 3)]
        #expect(isComplete(contract("A", "C"), lanes: mine))
        #expect(!isComplete(contract("A", "D"), lanes: mine))
        #expect(!isComplete(contract("A", "C"), lanes: [mine[0]]))
        // Rivals' lanes are not passed in, so a gap in my own network never counts.
        let (map, base) = scoringSetup()
        var s = base
        give(&s, 0, lanes: [0], contracts: [0])
        s.laneOwner[1] = 1
        s.players[1].lanes = [1]
        let scores = finalScores(s, map: map)
        #expect(scores[0].contractsCompleted == 0)
        #expect(scores[0].contractsLost == map.contracts[0].value)
    }

    @Test func spanCountsLoopOnceEach() {
        let lanes = [lane(0, "A", "B", 2), lane(1, "B", "C", 3), lane(2, "C", "A", 4), lane(3, "C", "D", 1)]
        #expect(greatSpan(lanes: lanes) == 10)
    }

    @Test func spanOfNoLanesIsZero() {
        #expect(greatSpan(lanes: []) == 0)
    }

    @Test func spanPicksLongerBranch() {
        let lanes = [lane(0, "A", "B", 2), lane(1, "B", "C", 3), lane(2, "B", "D", 1)]
        #expect(greatSpan(lanes: lanes) == 5)
    }

    @Test func spanTieBothScore() {
        let (map, base) = scoringSetup()
        var s = base
        give(&s, 0, lanes: [1], contracts: [])   // B-C 3
        give(&s, 1, lanes: [5], contracts: [])   // E-F 3
        let scores = finalScores(s, map: map)
        #expect(scores.map(\.span) == [3, 3])
        #expect(scores.map(\.spanBonus) == [10, 10])
    }

    @Test func noBonusWhenEveryoneHasZeroSpan() {
        let (map, s) = scoringSetup()
        let scores = finalScores(s, map: map)
        #expect(scores.map(\.span) == [0, 0])
        #expect(scores.map(\.spanBonus) == [0, 0])
    }

    @Test func lanePointsRecomputedFromOwnedLanes() {
        let (map, base) = scoringSetup()
        var s = base
        give(&s, 0, lanes: [0, 1], contracts: [])
        s.players[0].score = 999
        let scores = finalScores(s, map: map)
        #expect(scores[0].lanePoints == lanePoints(2) + lanePoints(3))
    }

    @Test func unfinishedContractSubtracts() {
        let (map, base) = scoringSetup()
        var s = base
        give(&s, 0, lanes: [0, 1], contracts: [0, 1])   // A-C done, A-D not
        let sc = finalScores(s, map: map)[0]
        #expect(sc.contractsGained == map.contracts[0].value)
        #expect(sc.contractsLost == map.contracts[1].value)
        #expect(sc.contractsCompleted == 1)
        #expect(sc.span == 5)
        #expect(sc.spanBonus == 10)
        #expect(sc.total == 2 + 4 + map.contracts[0].value - map.contracts[1].value + 10)
    }

    @Test func tiebreakMostContracts() {
        let a = FinalScore(player: 0, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 1, span: 0, spanBonus: 0, total: 20)
        let b = FinalScore(player: 1, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 3, span: 0, spanBonus: 0, total: 20)
        #expect(ranking([a, b]) == [[1], [0]])
    }

    @Test func tiebreakSpanHolder() {
        let a = FinalScore(player: 0, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 2, span: 0, spanBonus: 0, total: 20)
        let b = FinalScore(player: 1, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 2, span: 9, spanBonus: 10, total: 20)
        #expect(ranking([a, b]) == [[1], [0]])
    }

    @Test func totalBeatsTiebreakers() {
        let a = FinalScore(player: 0, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 9, span: 0, spanBonus: 0, total: 10)
        let b = FinalScore(player: 1, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 0, span: 0, spanBonus: 0, total: 11)
        #expect(ranking([a, b]) == [[1], [0]])
    }

    @Test func fullTieShared() {
        let a = FinalScore(player: 0, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 2, span: 4, spanBonus: 10, total: 30)
        let b = FinalScore(player: 1, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 2, span: 4, spanBonus: 10, total: 30)
        let c = FinalScore(player: 2, lanePoints: 0, contractsGained: 0, contractsLost: 0,
                           contractsCompleted: 0, span: 0, spanBonus: 0, total: 5)
        let groups = ranking([a, b, c])
        #expect(groups.first?.count == 2)
        #expect(Set(groups[0]) == [0, 1])
        #expect(groups[1] == [2])
    }
    @Test func spanTrailIsALongestTrail() {
        let fixtures: [(lanes: [Lane], length: Int)] = [
            ([lane(0, "A", "B", 2), lane(1, "B", "C", 3), lane(2, "C", "A", 4), lane(3, "C", "D", 1)], 10),
            ([lane(0, "A", "B", 2), lane(1, "B", "C", 3), lane(2, "B", "D", 1)], 5),
        ]
        for f in fixtures {
            let trail = greatSpanTrail(lanes: f.lanes)
            #expect(trail.reduce(0) { $0 + $1.length } == f.length)
            #expect(Set(trail.map(\.id)).count == trail.count)
            // A walk: start at the end of the first lane that the second lane does not touch,
            // then each lane must leave from the current endpoint.
            guard trail.count > 1 else { continue }
            var at = [trail[0].a, trail[0].b].first { ![trail[1].a, trail[1].b].contains($0) } ?? trail[0].a
            for l in trail {
                #expect(l.a == at || l.b == at)
                at = l.a == at ? l.b : l.a
            }
        }
        #expect(greatSpanTrail(lanes: []).isEmpty)
    }
}
