import Testing
@testable import StarsCore

private func fresh() -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    var s = e.newGame(GameConfig(houses: [.varn, .solace, .meridian], frontierHazards: false, seed: 7))
    s.phase = .awaitingAction
    s.current = 0
    return (e, s)
}

/// Nothing to draw, nothing to claim, no contracts left: the player is stuck.
private func stuck() -> (GameEngine, GameState) {
    var (e, s) = fresh()
    s.depot = []
    s.salvage = []
    s.exchange = Array(repeating: nil, count: 5)
    s.contractDeck = []
    for i in s.players.indices { s.players[i].hand = Hand() }
    return (e, s)
}

@Suite struct TurnTests {
    @Test func triggerGivesEveryoneOneMoreTurnIncludingTrigger() throws {
        var (e, s) = fresh()
        s.current = 1
        s.players[1].beacons = 2
        let events = e.endTurn(&s)
        #expect(events == [.finalRoundBegan(trigger: 1)])
        #expect(s.finalTurnsRemaining == 3)
        var order: [Int] = []
        for _ in 0..<3 {
            #expect(s.phase == .awaitingAction)
            order.append(s.current)
            _ = e.endTurn(&s)
        }
        #expect(order == [2, 0, 1])
        #expect(s.phase == .gameOver)
    }

    @Test func gameEndedEventEmittedOnFinalTurn() {
        var (e, s) = fresh()
        s.finalTurnsRemaining = 1
        #expect(e.endTurn(&s) == [.gameEnded])
        #expect(s.phase == .gameOver)
    }

    @Test func triggerAtExactlyThreeDoesNot() {
        var (e, s) = fresh()
        s.players[0].beacons = 3
        #expect(e.endTurn(&s).isEmpty)
        #expect(s.finalTurnsRemaining == nil)
        #expect(s.current == 1)
    }

    @Test func passOnlyWhenStuck() throws {
        var (e, s) = fresh()
        #expect(!e.legalActions(s).contains(.pass))
        #expect(throws: RuleError.passNotAllowed) { try e.apply(.pass, to: &s) }

        var (e2, s2) = stuck()
        #expect(e2.legalActions(s2) == [.pass])
        let events = try e2.apply(.pass, to: &s2)
        #expect(events.first == .passed(player: 0))
        #expect(s2.current == 1)
        #expect(s2.consecutivePasses == 1)
    }

    @Test func fullRoundOfPassesEndsGame() throws {
        var (e, s) = stuck()
        _ = try e.apply(.pass, to: &s)
        _ = try e.apply(.pass, to: &s)
        #expect(s.phase == .awaitingAction)
        let events = try e.apply(.pass, to: &s)
        #expect(events.last == .gameEnded)
        #expect(s.phase == .gameOver)
    }

    @Test func nonPassResetsConsecutivePasses() {
        var (e, s) = fresh()
        s.consecutivePasses = 2
        _ = e.endTurn(&s)
        #expect(s.consecutivePasses == 0)
    }

    @Test func actionAfterGameOverThrows() {
        var (e, s) = fresh()
        s.phase = .gameOver
        #expect(e.legalActions(s).isEmpty)
        for a: Action in [.drawBlind, .pass, .drawContracts, .keepContracts([0]), .drawExchange(slot: 0)] {
            #expect(throws: RuleError.gameOver) { try e.apply(a, to: &s) }
        }
    }
}
