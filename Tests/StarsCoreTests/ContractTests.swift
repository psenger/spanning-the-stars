import Testing
@testable import StarsCore

private func newState(houses: [House] = [.varn, .solace, .meridian]) -> (GameEngine, GameState) {
    let e = GameEngine(map: .big)
    return (e, e.newGame(GameConfig(houses: houses, frontierHazards: false, seed: 7)))
}

@Suite struct ContractSetupTests {
    @Test func setupKeepTwoAdvancesSeat() throws {
        var (e, s) = newState()
        let offer = s.pendingOffers[0]
        let events = try e.apply(.keepContracts([offer[0], offer[2]]), to: &s)
        #expect(s.players[0].contracts == [offer[0], offer[2]])
        #expect(s.setupReturns == [offer[1], offer[3]])
        #expect(s.current == 1)
        #expect(s.phase == .setupContracts(offered: s.pendingOffers[1]))
        #expect(events == [.keptContracts(player: 0, count: 2)])
    }

    @Test func setupKeepOneThrows() {
        var (e, s) = newState()
        let offer = s.pendingOffers[0]
        #expect(throws: RuleError.mustKeepAtLeast(2)) {
            try e.apply(.keepContracts([offer[0]]), to: &s)
        }
    }

    @Test func setupKeepUnofferedThrows() {
        var (e, s) = newState()
        let other = s.pendingOffers[1]
        #expect(throws: RuleError.notOffered) {
            try e.apply(.keepContracts([other[0], other[1]]), to: &s)
        }
    }

    @Test func setupDuplicateIdsThrow() {
        var (e, s) = newState()
        let offer = s.pendingOffers[0]
        #expect(throws: RuleError.notOffered) {
            try e.apply(.keepContracts([offer[0], offer[0], offer[1]]), to: &s)
        }
    }

    @Test func afterLastSeatPlayStartsAtFirstPlayer() throws {
        var (e, s) = newState()
        let deckBefore = s.contractDeck
        for seat in 0..<3 {
            let offer = s.pendingOffers[seat]
            _ = try e.apply(.keepContracts(Array(offer.prefix(2))), to: &s)
        }
        #expect(s.current == s.firstPlayer)
        #expect(s.phase == .awaitingAction)
        let returned = s.pendingOffers.flatMap { $0.suffix(2) }
        #expect(s.contractDeck.count == deckBefore.count + returned.count)
        #expect(Set(s.contractDeck[0..<returned.count]) == Set(returned))
        #expect(Array(s.contractDeck[returned.count...]) == deckBefore)
    }

    @Test func setupLegalActionsAreEverySubsetOfAtLeastTwo() {
        let (e, s) = newState()
        let actions = e.legalActions(s)
        #expect(actions.count == 11)
        #expect(Set(actions).count == 11)
    }
}

private func playingState() throws -> (GameEngine, GameState) {
    var (e, s) = newState()
    for seat in 0..<3 { _ = try e.apply(.keepContracts(Array(s.pendingOffers[seat].prefix(2))), to: &s) }
    return (e, s)
}

@Suite struct ContractDrawTests {
    @Test func drawThreeKeepOne() throws {
        var (e, s) = try playingState()
        let seat = s.current
        let top3 = Array(s.contractDeck.suffix(3))
        let deckCount = s.contractDeck.count
        _ = try e.apply(.drawContracts, to: &s)
        #expect(s.phase == .choosingContracts(offered: Array(top3.reversed())))
        #expect(s.contractDeck.count == deckCount - 3)
        let events = try e.apply(.keepContracts([top3[0]]), to: &s)
        #expect(s.players[seat].contracts.suffix(1) == [top3[0]])
        #expect(s.contractDeck.count == deckCount - 1)
        #expect(events.contains(.keptContracts(player: seat, count: 1)))
        #expect(s.current == (seat + 1) % 3)
        #expect(s.phase == .awaitingAction)
    }

    @Test func drawWithTwoLeftOffersTwo() throws {
        var (e, s) = try playingState()
        s.contractDeck = Array(s.contractDeck.prefix(2))
        _ = try e.apply(.drawContracts, to: &s)
        guard case let .choosingContracts(offered) = s.phase else { Issue.record("wrong phase"); return }
        #expect(offered.count == 2)
        #expect(s.contractDeck.isEmpty)
    }

    @Test func keepZeroThrows() throws {
        var (e, s) = try playingState()
        _ = try e.apply(.drawContracts, to: &s)
        #expect(throws: RuleError.mustKeepAtLeast(1)) {
            try e.apply(.keepContracts([]), to: &s)
        }
    }

    @Test func keepUnofferedOrDuplicateThrows() throws {
        var (e, s) = try playingState()
        _ = try e.apply(.drawContracts, to: &s)
        guard case let .choosingContracts(offered) = s.phase else { return }
        #expect(throws: RuleError.notOffered) { try e.apply(.keepContracts([-1]), to: &s) }
        #expect(throws: RuleError.notOffered) { try e.apply(.keepContracts([offered[0], offered[0]]), to: &s) }
    }

    @Test func returnedGoToBottom() throws {
        var (e, s) = try playingState()
        let deckBefore = s.contractDeck
        _ = try e.apply(.drawContracts, to: &s)
        guard case let .choosingContracts(offered) = s.phase else { return }
        _ = try e.apply(.keepContracts([offered[1]]), to: &s)
        #expect(Array(s.contractDeck.prefix(2)) == [offered[0], offered[2]])
        #expect(Array(s.contractDeck.dropFirst(2)) == Array(deckBefore.dropLast(3)))
    }

    @Test func emptyDeckThrows() throws {
        var (e, s) = try playingState()
        s.contractDeck = []
        #expect(throws: RuleError.contractDeckEmpty) { try e.apply(.drawContracts, to: &s) }
        #expect(!e.legalActions(s).contains(.drawContracts))
    }

    @Test func legalActionsIncludeDrawContractsAndSubsets() throws {
        var (e, s) = try playingState()
        #expect(e.legalActions(s).contains(.drawContracts))
        _ = try e.apply(.drawContracts, to: &s)
        guard case let .choosingContracts(offered) = s.phase else { return }
        let actions = e.legalActions(s)
        #expect(actions.count == 7)
        #expect(Set(actions).count == 7)
        for a in actions {
            guard case let .keepContracts(ids) = a else { Issue.record("not keep"); continue }
            #expect(!ids.isEmpty && Set(ids).isSubset(of: offered))
        }
    }
}
