import Testing
@testable import StarsCore

private let g = MapGraph(map: .tiny)

@Suite struct RoutePlannerTests {
    @Test func shortestRouteOnAnEmptyBoard() {
        #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [:], playerCount: 2)
                == Route(toClaim: [0, 1, 2], cost: 6))
    }

    @Test func blockedLinkForcesADetour() {
        // Rival owns B-C: A to D goes A-B, B-E, E-D.
        #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [1: 1], playerCount: 2)
                == Route(toClaim: [0, 7, 4], cost: 9))
    }

    @Test func ownedLinksCostNothing() {
        #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [0: 0, 1: 0], playerCount: 2)
                == Route(toClaim: [2], cost: 1))
    }

    @Test func impossibleGoalIsNil() {
        // Rival owns A-B and A-F: A is cut off.
        #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [0: 1, 6: 1], playerCount: 2) == nil)
    }

    @Test func closedTwinIsBlockedWithThreeOrFewerHouses() {
        // Rival owns twin 2; with 2 Houses twin 3 is closed, so C-D is unreachable directly.
        #expect(g.route(from: "C", to: "D", seat: 0, laneOwner: [2: 1], playerCount: 2)
                == Route(toClaim: [1, 7, 4], cost: 10))
        #expect(g.route(from: "C", to: "D", seat: 0, laneOwner: [2: 1], playerCount: 4)
                == Route(toClaim: [3], cost: 1))
    }

    @Test func alreadyJoinedCostsZero() {
        #expect(g.route(from: "A", to: "C", seat: 0, laneOwner: [0: 0, 1: 0], playerCount: 2)
                == Route(toClaim: [], cost: 0))
    }

    @Test func freeLanesAreSharedBetweenGoals() {
        #expect(g.route(from: "A", to: "E", seat: 0, laneOwner: [:], playerCount: 2, free: [0, 7])
                == Route(toClaim: [0, 7], cost: 0))
    }

    @Test func tiesPreferFewerLanesThenLowerLaneIds() {
        // C-D on an empty board: twins 2 and 3 both cost 1, the lower id wins.
        #expect(g.route(from: "C", to: "D", seat: 0, laneOwner: [:], playerCount: 2)
                == Route(toClaim: [2], cost: 1))
        // B to E: B-E direct (1 lane) ties at cost 0 with B-C, C-D, D-E (3 lanes) once all are free.
        #expect(g.route(from: "B", to: "E", seat: 0, laneOwner: [:], playerCount: 2, free: [1, 2, 4, 7])
                == Route(toClaim: [7], cost: 0))
    }

    @Test func agreesWithTheMapsShortestPathOnAnEmptyBoard() {
        let map = GalaxyMap.standard
        let graph = MapGraph(map: map)
        #expect(!map.contracts.isEmpty)
        for c in map.contracts {
            let route = graph.route(from: c.a, to: c.b, seat: 0, laneOwner: [:], playerCount: 2)
            #expect(route?.cost == shortestPath(map, c.a, c.b), "contract \(c.id) \(c.a)-\(c.b)")
        }
    }
}
