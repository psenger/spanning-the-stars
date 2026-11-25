import Testing
@testable import StarsCore

private let red = Card.resource(.red)
private let blue = Card.resource(.blue)
private let green = Card.resource(.green)

private func arranged(depot: [Card], exchange: [Card?], salvage: [Card] = []) -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    var s = e.newGame(GameConfig(houses: [.varn, .solace, .meridian], frontierHazards: false, seed: 7))
    s.depot = depot
    s.exchange = exchange
    s.salvage = salvage
    s.phase = .awaitingAction
    s.current = 0
    for i in s.players.indices { s.players[i].hand = Hand() }
    return (e, s)
}

@Suite struct DrawTests {
    @Test func blindThenBlindEndsTurn() throws {
        var (e, s) = arranged(depot: [red, blue, green], exchange: [red, red, blue, blue, green])
        _ = try e.apply(.drawBlind, to: &s)
        #expect(s.phase == .drawingSecondCard)
        #expect(s.current == 0)
        _ = try e.apply(.drawBlind, to: &s)
        #expect(s.phase == .awaitingAction)
        #expect(s.current == 1)
        #expect(s.players[0].hand.total == 2)
    }

    @Test func faceUpCoreFirstEndsTurn() throws {
        var (e, s) = arranged(depot: [red, blue, green], exchange: [.core, red, blue, blue, green])
        let events = try e.apply(.drawExchange(slot: 0), to: &s)
        #expect(s.current == 1)
        #expect(s.phase == .awaitingAction)
        #expect(s.players[0].hand.count(.core) == 1)
        #expect(events.first == .drewExchange(player: 0, card: .core))
        #expect(s.exchange[0] == green)
    }

    @Test func faceUpCoreSecondThrows() throws {
        var (e, s) = arranged(depot: [red, blue, green], exchange: [.core, red, blue, blue, green])
        _ = try e.apply(.drawExchange(slot: 1), to: &s)
        #expect(s.phase == .drawingSecondCard)
        #expect(throws: RuleError.coreMustBeFirst) {
            try e.apply(.drawExchange(slot: 0), to: &s)
        }
    }

    @Test func blindCoreStillDrawsTwo() throws {
        var (e, s) = arranged(depot: [red, blue, .core], exchange: [red, red, blue, blue, green])
        _ = try e.apply(.drawBlind, to: &s)
        #expect(s.players[0].hand.count(.core) == 1)
        #expect(s.phase == .drawingSecondCard)
        #expect(s.current == 0)
    }

    @Test func refillAfterPickRevealsCoreNotTakeable() throws {
        var (e, s) = arranged(depot: [red, blue, .core], exchange: [red, red, blue, blue, green])
        _ = try e.apply(.drawExchange(slot: 0), to: &s)
        #expect(s.exchange[0] == .core)
        #expect(s.phase == .drawingSecondCard)
        let legal = e.legalActions(s)
        #expect(!legal.contains(.drawExchange(slot: 0)))
        #expect(legal.contains(.drawExchange(slot: 1)))
        #expect(legal.contains(.drawBlind))
        #expect(throws: RuleError.coreMustBeFirst) {
            try e.apply(.drawExchange(slot: 0), to: &s)
        }
    }

    @Test func depotEmptyReshufflesSalvage() throws {
        var (e, s) = arranged(depot: [], exchange: [red, red, blue, blue, green], salvage: [red, blue, green])
        _ = try e.apply(.drawBlind, to: &s)
        #expect(s.salvage.isEmpty)
        #expect(s.depot.count == 2)
        #expect(s.players[0].hand.total == 1)
    }

    @Test func noCardsAnywhereThrows() {
        var (e, s) = arranged(depot: [], exchange: [red, red, blue, blue, green])
        #expect(throws: RuleError.noCardsToDraw) {
            try e.apply(.drawBlind, to: &s)
        }
        #expect(!e.legalActions(s).contains(.drawBlind))
        #expect(s.phase == .awaitingAction)
    }

    @Test func emptySlotThrows() {
        var (e, s) = arranged(depot: [], exchange: [red, nil, nil, nil, nil])
        #expect(throws: RuleError.slotEmpty) {
            try e.apply(.drawExchange(slot: 1), to: &s)
        }
    }

    @Test func turnEndsWhenNoSecondCardExists() throws {
        var (e, s) = arranged(depot: [], exchange: [red, nil, nil, nil, nil])
        _ = try e.apply(.drawExchange(slot: 0), to: &s)
        #expect(s.current == 1)
        #expect(s.phase == .awaitingAction)
    }

    @Test func turnEndsWhenOnlyCoresRemainForSecond() throws {
        var (e, s) = arranged(depot: [], exchange: [red, .core, .core, nil, nil])
        _ = try e.apply(.drawExchange(slot: 0), to: &s)
        #expect(s.current == 1)
    }

    @Test func blindDrawEventHidesCard() throws {
        var (e, s) = arranged(depot: [red, blue], exchange: [red, red, blue, blue, green])
        let events = try e.apply(.drawBlind, to: &s)
        #expect(events == [.drewBlind(player: 0)])
    }
    // Review Focus 2: once the Exchange runs empty, cards that return later must refill it.
    @Test func claimRefillsEmptyExchange() throws {
        var (e, s) = arranged(depot: [], exchange: [nil, nil, nil, nil, nil])
        s.players[0].hand.add(red, 2)
        _ = try e.apply(.claim(laneID: 0, payment: Payment([red: 2])), to: &s)
        #expect(s.exchange == [red, red, nil, nil, nil])
        #expect(s.salvage.isEmpty)
        #expect(s.depot.isEmpty)
    }

    @Test func blindDrawTurnRefillsEmptyExchange() throws {
        var (e, s) = arranged(depot: [], exchange: [nil, nil, nil, nil, nil],
                              salvage: [red, red, blue, blue, green, green, red, blue])
        _ = try e.apply(.drawBlind, to: &s)
        _ = try e.apply(.drawBlind, to: &s)
        #expect(s.current == 1)
        #expect(s.exchange.compactMap { $0 }.count == 5)
        #expect(s.depot.count == 1)
    }

    @Test func turnEndRefillReportsResets() throws {
        var (e, s) = arranged(depot: [], exchange: [.core, .core, .core, nil, nil])
        s.players[0].hand.add(red, 3)
        let events = try e.apply(.claim(laneID: 1, payment: Payment([red: 3])), to: &s)
        #expect(events.contains(.exchangeReset))
        #expect(s.log.suffix(events.count) == events[...])
        #expect(s.exchange.compactMap { $0 }.count == 5)
    }

    // Section 10: with too few non-Core cards, the Exchange is left as it is.
    @Test func turnEndRefillKeepsResetStop() throws {
        var (e, s) = arranged(depot: [], exchange: [.core, .core, .core, nil, nil])
        s.players[0].hand.add(red, 2)
        let events = try e.apply(.claim(laneID: 0, payment: Payment([red: 2])), to: &s)
        #expect(!events.contains(.exchangeReset))
        #expect(s.exchange == [.core, .core, .core, red, red])
    }
    @Test func fullStuckExchangeLeftAtTurnEnd() throws {
        var (e, s) = arranged(depot: [], exchange: [.core, .core, .core, red, blue])
        s.players[0].hand.add(red, 3)
        let events = try e.apply(.claim(laneID: 1, payment: Payment([red: 3])), to: &s)
        #expect(!events.contains(.exchangeReset))
        #expect(s.exchange == [.core, .core, .core, red, blue])
        #expect(s.salvage == [red, red, red])
    }
}
