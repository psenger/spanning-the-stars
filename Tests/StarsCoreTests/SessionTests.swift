import Testing
@testable import StarsCore

@MainActor @Suite struct SessionTests {
    private func session(seed: UInt64 = 7, houses: [House] = [.varn, .solace]) -> GameSession {
        GameSession(config: GameConfig(houses: houses, frontierHazards: false, seed: seed))
    }

    private func keepFirstTwo(_ s: GameSession) {
        guard case let .setupContracts(offered) = s.state.phase else { return }
        s.perform(.keepContracts(Array(offered.prefix(2))))
    }

    private func toPlay(_ s: GameSession) {
        while case .setupContracts = s.state.phase {
            s.reveal()
            keepFirstTwo(s)
        }
        s.reveal()
    }

    @Test func startsAtHandoff() {
        let s = session()
        #expect(s.screen == .handoff(player: 0))
        #expect(s.activePlayer == 0)
        #expect(s.lastError == nil)
    }

    @Test func revealShowsPlaying() {
        let s = session()
        s.reveal()
        #expect(s.screen == .playing)
    }

    @Test func setupPickLeadsToNextHandoff() {
        let s = session()
        s.reveal()
        keepFirstTwo(s)
        #expect(s.screen == .handoff(player: 1))
        #expect(s.activePlayer == 1)
    }

    @Test func firstDrawStaysPlaying() {
        let s = session()
        toPlay(s)
        s.perform(.drawBlind)
        #expect(s.state.phase == .drawingSecondCard)
        #expect(s.screen == .playing)
    }

    @Test func secondDrawLeadsToHandoff() {
        let s = session()
        toPlay(s)
        let before = s.activePlayer
        s.perform(.drawBlind)
        s.perform(.drawBlind)
        #expect(s.activePlayer != before)
        #expect(s.screen == .handoff(player: s.activePlayer))
        #expect(s.recentEvents.count == 2)
    }

    @Test func illegalActionKeepsScreenAndSetsError() {
        let s = session()
        s.reveal()
        s.perform(.drawBlind)
        #expect(s.lastError == .wrongPhase)
        #expect(s.screen == .playing)
        keepFirstTwo(s)
        #expect(s.lastError == nil)
    }

    @Test func eventsNeverExposeHiddenInfo() {
        let s = session(seed: 3)
        var picker = SeededRNG(seed: 3)
        var steps = 0
        while s.screen != .finalReview, steps < 3000 {
            s.reveal()
            guard let action = s.engine.legalActions(s.state).randomElement(using: &picker) else { break }
            s.perform(action)
            steps += 1
        }
        #expect(s.screen == .finalReview)
        #expect(!s.state.log.isEmpty)
        #expect(s.state.log.contains { if case .drewBlind = $0 { true } else { false } })
        #expect(s.state.log.contains { if case .keptContracts = $0 { true } else { false } })
        for event in s.state.log {
            switch event {
            case .drewBlind(let p): _ = p   // player only, no card
            case .keptContracts(let p, let n): _ = (p, n)   // count only, no ids
            case .drewExchange(_, let card): _ = card   // face-up card, public
            case .exchangeReset, .claimed, .passed, .finalRoundBegan, .gameEnded: break
            }
        }
        let text = s.state.log.map { "\($0)" }
        #expect(text.filter { $0.hasPrefix("drewBlind") }.allSatisfy { !$0.contains("card") })
        #expect(text.filter { $0.hasPrefix("keptContracts") }.allSatisfy { $0.contains("count") && !$0.contains("[") })
    }

    @Test func performDuringHandoffDoesNothing() {
        let s = session()
        let before = s.state.log.count
        guard case let .setupContracts(offered) = s.state.phase else { return }
        s.perform(.keepContracts(Array(offered.prefix(2))))
        #expect(s.screen == .handoff(player: 0))
        #expect(s.state.phase == .setupContracts(offered: offered))
        #expect(s.state.log.count == before)
    }

    @Test func performAfterGameOverDoesNothing() {
        let s = session(seed: 3)
        var picker = SeededRNG(seed: 3)
        while s.screen != .finalReview {
            s.reveal()
            guard let a = s.engine.legalActions(s.state).randomElement(using: &picker) else { break }
            s.perform(a)
        }
        let log = s.state.log.count
        s.perform(.pass)
        #expect(s.screen == .finalReview)
        #expect(s.state.log.count == log)
    }

    @Test func errorClearedByRevealAndHandoff() {
        let s = session()
        s.reveal()
        s.perform(.drawBlind)
        #expect(s.lastError == .wrongPhase)
        keepFirstTwo(s)   // hand-off begins
        #expect(s.lastError == nil)
        s.reveal()
        s.perform(.drawBlind)
        #expect(s.lastError == .wrongPhase)
        s.perform(.drawBlind)   // still an error, then clear via a real action
        keepFirstTwo(s)
        #expect(s.lastError == nil)
    }
}
