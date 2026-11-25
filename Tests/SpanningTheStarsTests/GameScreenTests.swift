import Testing
@testable import SpanningTheStars
@testable import StarsCore

@MainActor @Suite struct GameScreenTests {
    private let engine = GameEngine(map: .standard)

    /// A game past setup, at the first House's main action.
    private func playing(houses: [House] = [.varn, .solace], hazards: Bool = false) -> GameState {
        var s = engine.newGame(GameConfig(houses: houses, frontierHazards: hazards, seed: 3))
        s.phase = .awaitingAction
        s.current = 0
        return s
    }

    // MARK: Debug state (Review Focus 5)

    @Test func bigHandsDebugStateMeetsReviewFocus5() {
        let r = DebugGames.bigHands
        let s = DebugGames.state(r)
        let focus = s.players[r.focus]
        #expect(s.players.count == 5)
        #expect(s.config.frontierHazards)
        #expect(s.current == r.focus)
        #expect(s.phase == .awaitingAction)
        #expect(s.finalTurnsRemaining == nil)
        #expect(focus.hand.total >= 45)
        #expect(focus.contracts.count == 12)
        #expect(s.laneOwner.count >= 10)
        #expect(s.exchange.allSatisfy { $0 != nil })
        #expect(ContractsPanel.rows(focus, map: .standard).contains { $0.complete })
    }

    @Test func debugStatesAreDeterministic() {
        #expect(DebugGames.state(DebugGames.bigHands) == DebugGames.state(DebugGames.bigHands))
        #expect(DebugGames.state(DebugGames.twoHouses) == DebugGames.state(DebugGames.twoHouses))
    }

    @Test func debugSessionOpensOnThePlayingScreen() {
        let session = DebugGames.session(DebugGames.twoHouses)
        #expect(session.screen == .playing)
        #expect(session.state.players.count == 2)
        #expect(!session.state.config.frontierHazards)
    }

    // MARK: Turn options

    @Test func secondPickExcludesFaceUpCoreAndClaims() {
        var s = playing()
        s.phase = .drawingSecondCard
        s.exchange = [.core, .resource(.red), nil, .resource(.blue), .core]
        let options = TurnOptions(actions: engine.legalActions(s))
        #expect(options.exchangeSlots == [1, 3])
        #expect(options.canDrawBlind)
        #expect(!options.canDrawContracts)
        #expect(options.payments.isEmpty)
        #expect(!options.mustPass)
    }

    @Test func claimPaymentsMatchPaymentOptions() {
        var s = playing()
        s.players[0].hand = Hand()
        s.players[0].hand.add(.resource(.red), 3)
        s.players[0].hand.add(.core, 1)
        let options = TurnOptions(actions: engine.legalActions(s))
        let lane = engine.map.lane(67) // Kessra to Forgeholm, red, length 2
        #expect(options.payments[67] == paymentOptions(for: lane, hand: s.players[0].hand, hazards: false))
        #expect(options.payments[67]?.first == Payment([.resource(.red): 2]))
    }

    @Test func cacheRecomputesOnlyWhenStateChanges() {
        let cache = TurnOptionsCache()
        var s = playing()
        _ = cache.options(for: s, engine: engine)
        _ = cache.options(for: s, engine: engine)
        #expect(cache.computations == 1)
        _ = try? engine.apply(.drawBlind, to: &s)
        let second = cache.options(for: s, engine: engine)
        #expect(cache.computations == 2)
        #expect(second.payments.isEmpty)
    }

    // MARK: Claim sheet

    @Test func claimBlockedWithoutBeacons() {
        var s = playing()
        s.players[0].beacons = 1
        s.players[0].hand.add(.resource(.red), 2)
        let a = ClaimSheet.availability(engine.map.lane(67), state: s, engine: engine,
                                        options: TurnOptions(actions: engine.legalActions(s)))
        guard case .blocked(let message) = a else { Issue.record("expected blocked, got \(a)"); return }
        #expect(message.hasPrefix("Not enough beacons"))
        #expect(message.contains("needs 2"))
    }

    @Test func claimBlockedWhenTwinClosesCorridor() {
        var s = playing()
        s.laneOwner[68] = 1
        s.players[1].lanes = [68]
        s.players[0].hand.add(.resource(.red), 2)
        let a = ClaimSheet.availability(engine.map.lane(67), state: s, engine: engine,
                                        options: TurnOptions(actions: engine.legalActions(s)))
        guard case .blocked(let message) = a else { Issue.record("expected blocked, got \(a)"); return }
        #expect(message.hasPrefix("Lane closed"))
    }

    @Test func claimBlockedDuringSecondPickAndWhenUnaffordable() {
        var s = playing()
        s.players[0].hand = Hand()
        let lane = engine.map.lane(67)
        let poor = ClaimSheet.availability(lane, state: s, engine: engine,
                                           options: TurnOptions(actions: engine.legalActions(s)))
        #expect(poor == .blocked("Your hand cannot pay for this lane. It costs 2 Plasma Fuel."))
        s.phase = .drawingSecondCard
        let mid = ClaimSheet.availability(lane, state: s, engine: engine,
                                          options: TurnOptions(actions: engine.legalActions(s)))
        guard case .blocked(let message) = mid else { Issue.record("expected blocked"); return }
        #expect(message.hasPrefix("Take your second Resource Card first"))
    }

    // MARK: Concord Log

    private let houses: [PlayerState] = [House.varn, .solace, .meridian, .ashkar].map {
        PlayerState(house: $0, kind: .human, hand: Hand(), contracts: [])
    }

    private func texts(_ log: [GameEvent], limit: Int = 8) -> [String] {
        ConcordLog.recent(log, players: houses, map: .standard, limit: limit).map(\.text)
    }

    @Test func logMergesConsecutiveResets() {
        let log: [GameEvent] = [.exchangeReset, .claimed(player: 3, laneID: 67, points: 2),
                                .drewExchange(player: 2, card: .resource(.blue)),
                                .exchangeReset, .exchangeReset, .exchangeReset]
        #expect(texts(log) == [
            "The Exchange was refreshed",
            "Meridian Collective took Coolant Ice from the Exchange",
            "House Ashkar anchored Kessra to Forgeholm (+2)",
            "The Exchange was refreshed",
        ])
    }

    @Test func logMergesOneHousesBlindDrawsAndNeverNamesTheCard() {
        let log: [GameEvent] = [.drewBlind(player: 0), .drewBlind(player: 1), .drewBlind(player: 1)]
        #expect(texts(log) == [
            "The Solace Trust requisitioned 2 Resource Cards",
            "Varn Industrial requisitioned a Resource Card",
        ])
    }

    @Test func logKeepsTheNewestLinesOnly() {
        let log: [GameEvent] = (0..<12).map { .passed(player: $0 % 4) } + [.keptContracts(player: 1, count: 2)]
        let lines = texts(log)
        #expect(lines.count == 8)
        #expect(lines.first == "The Solace Trust accepted 2 Concord Contracts")
        #expect(lines.last == "The Solace Trust held position")  // pass 5 of 0...11
    }

    @Test func logMergeAtTheLimitStillCountsTheWholeRun() {
        let log: [GameEvent] = [.exchangeReset, .exchangeReset, .passed(player: 0)]
        #expect(texts(log, limit: 2) == ["Varn Industrial held position", "The Exchange was refreshed"])
    }

    // MARK: Hand and contracts

    @Test func handStacksFollowColorOrderWithCoresLast() {
        var hand = Hand()
        hand.add(.core, 2)
        hand.add(.resource(.orange), 1)
        hand.add(.resource(.red), 4)
        hand.add(.resource(.blue), 3)
        let stacks = HandTray.stacks(hand)
        #expect(stacks.map(\.card) == [.resource(.red), .resource(.blue), .resource(.orange), .core])
        #expect(stacks.map(\.count) == [4, 3, 1, 2])
    }

    @Test func contractRowsCheckCompletionFromOwnedLanes() {
        let map = GalaxyMap.standard
        let id = map.contracts.firstIndex { $0.a == "forgeholm" && $0.b == "cinderfall" }!
        var p = PlayerState(house: .varn, kind: .human, hand: Hand(), contracts: [id, 0])
        p.lanes = [70]  // Forgeholm to Slagstar only
        #expect(ContractsPanel.rows(p, map: map).map(\.complete) == [false, false])
        p.lanes = [70, 73]  // then Slagstar to Cinderfall
        #expect(ContractsPanel.rows(p, map: map).map(\.complete) == [true, false])
    }
    // MARK: Privacy (Review Focus 3)

    @Test func secretsShowOnlyWhilePlaying() {
        var hand = Hand()
        hand.add(.resource(.red), 3)
        let p = PlayerState(house: .varn, kind: .human, hand: hand, contracts: [1, 2])
        let playing = Secrets(screen: .playing, player: p)
        #expect(playing.shown)
        #expect(playing.hand == hand)
        for screen: GameSession.Screen in [.handoff(player: 0), .handoff(player: 1), .finalReview] {
            let hidden = Secrets(screen: screen, player: p)
            #expect(!hidden.shown)
            #expect(hidden.hand == Hand())
        }
    }
}
