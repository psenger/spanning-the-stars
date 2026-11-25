import Foundation
import Testing
@testable import SpanningTheStars
@testable import StarsCore

@MainActor @Suite struct FlowScreenTests {
    private func score(_ player: Int, total: Int, completed: Int = 0, bonus: Int = 0) -> FinalScore {
        FinalScore(player: player, lanePoints: total - bonus, contractsGained: 0, contractsLost: 0,
                   contractsCompleted: completed, span: 0, spanBonus: bonus, total: total)
    }

    private let houses: [House] = [.varn, .solace, .meridian]

    // MARK: Contract picks (M5)

    @Test func contractPickMinimumIsTwoAtSetupAndOneInGame() {
        #expect(ContractPickView.pick(for: .setupContracts(offered: [1, 2, 3, 4]))?.minimum == 2)
        #expect(ContractPickView.pick(for: .choosingContracts(offered: [5, 6]))?.minimum == 1)
        #expect(ContractPickView.pick(for: .choosingContracts(offered: [5, 6]))?.offered == [5, 6])
        #expect(ContractPickView.pick(for: .awaitingAction) == nil)
        #expect(ContractPickView.pick(for: .drawingSecondCard) == nil)
    }

    // MARK: Final Review

    @Test func verdictClearWinner() {
        let scores = [score(0, total: 40), score(1, total: 55), score(2, total: 12)]
        let v = FinalReview.verdict(scores, ranking: ranking(scores), houses: houses)
        #expect(v.headline == "The Solace Trust wins the Charter")
        #expect(v.reason == "Highest Concord Standing: 55.")
    }

    @Test func verdictTieBrokenByContracts() {
        let scores = [score(0, total: 50, completed: 3), score(1, total: 50, completed: 5), score(2, total: 12)]
        let v = FinalReview.verdict(scores, ranking: ranking(scores), houses: houses)
        #expect(v.headline == "The Solace Trust wins the Charter")
        #expect(v.reason == "Tied on 50 Standing; wins on fulfilled Contracts, 5 to 3.")
    }

    @Test func verdictTieBrokenBySpan() {
        let scores = [score(0, total: 50, completed: 3, bonus: 10), score(1, total: 50, completed: 3), score(2, total: 1)]
        let v = FinalReview.verdict(scores, ranking: ranking(scores), houses: houses)
        #expect(v.headline == "Varn Industrial wins the Charter")
        #expect(v.reason.hasSuffix("wins by holding the Great Span Award."))
    }

    @Test func verdictSharedVictory() {
        let scores = [score(0, total: 50, completed: 3), score(1, total: 12), score(2, total: 50, completed: 3)]
        let v = FinalReview.verdict(scores, ranking: ranking(scores), houses: houses)
        #expect(v.headline == "Shared victory: Varn Industrial and Meridian Collective")
    }

    @Test func finishedDebugGameReviewsOnce() {
        let state = DebugGames.state(DebugGames.finished)
        #expect(state.phase == .gameOver)
        let cache = FinalReviewCache()
        let review = cache.review(for: state, map: .standard)
        _ = cache.review(for: state, map: .standard)
        #expect(cache.computations == 1)
        #expect(review.scores == finalScores(state, map: .standard))
        #expect(review.contracts.map(\.count) == state.players.map(\.contracts.count))
        // The highlighted span belongs to award holders and matches their span length.
        let holders = review.scores.filter { $0.spanBonus > 0 }
        #expect(!holders.isEmpty)
        let owners = Set(review.spanLanes.compactMap { state.laneOwner[$0] })
        #expect(owners == Set(holders.map(\.player)))
    }

    // MARK: Codex

    @Test func codexParsesTheRules() {
        let blocks = CodexBlock.parse(CodexText.load())
        #expect(blocks.first == .heading(level: 1, text: "The Concord Codex: Rules of Spanning the Stars"))
        #expect(blocks.contains(.heading(level: 2, text: "11. Variant: Frontier Hazards (optional, chosen at setup)")))
        #expect(blocks.contains(.table(header: ["Lane length", "1", "2", "3", "4", "5", "6"],
                                       rows: [["Standing", "1", "2", "4", "7", "10", "15"]])))
        #expect(blocks.contains(.item(marker: "1.", text: "Requisition Resources")))
        #expect(blocks.contains { if case .quote = $0 { true } else { false } })
    }

    // MARK: App model

    @Test func newCharterOpensAtTheFirstHandoff() {
        let model = AppModel(store: InMemoryGameStore(), saves: InMemorySaveSlots())
        #expect(model.route == .title)
        #expect(!model.canContinue)
        #expect(!model.canSave)
        model.openSetup()
        model.closeSetup()
        #expect(model.route == .title)
        model.startNewCharter(houses: [.varn, .ashkar], hazards: true)
        #expect(model.route == .game)
        #expect(model.session?.screen == .handoff(player: 0))
        #expect(model.session?.state.config.frontierHazards == true)
        #expect(model.canSave)
        model.openSetup()
        model.closeSetup()
        #expect(model.route == .game)
    }

    @Test func continueAndLoadLandOnTheHandoff() throws {
        let store = InMemoryGameStore()
        let slots = InMemorySaveSlots()
        let first = AppModel(store: store, saves: slots)
        first.startNewCharter(houses: [.varn, .solace], hazards: false)
        let session = try #require(first.session)
        session.reveal()
        if case .setupContracts(let offered) = session.state.phase { session.perform(.keepContracts(Array(offered.prefix(2)))) }
        try first.saveGame(named: "Mid", replacing: nil)

        let relaunched = AppModel(store: store, saves: slots)
        #expect(relaunched.canContinue)
        relaunched.continueCharter()
        #expect(relaunched.session?.screen == .handoff(player: 1))

        let id = try #require(relaunched.savedGames().first?.id)
        try relaunched.loadGame(id: id)
        #expect(relaunched.route == .game)
        #expect(relaunched.session?.state == session.state)
        #expect(relaunched.session?.screen == .handoff(player: session.state.current))
    }

    @Test func titleReturnForgetsTheGame() {
        let model = AppModel(store: InMemoryGameStore(), saves: InMemorySaveSlots())
        model.startNewCharter(houses: [.varn, .solace], hazards: false)
        model.returnToTitle()
        #expect(model.session == nil)
        #expect(model.route == .title)
        #expect(!model.gameInProgress)
    }

    @Test func newCharterAsksBeforeReplacingAGame() {
        let model = AppModel(store: InMemoryGameStore(), saves: InMemorySaveSlots())
        model.requestNewCharter()
        #expect(!model.confirmingNewCharter)
        #expect(model.route == .setup)

        model.startNewCharter(houses: [.varn, .solace], hazards: false)
        model.requestNewCharter()
        #expect(model.confirmingNewCharter)
        #expect(model.route == .game)   // nothing changes until Abandon

        model.confirmingNewCharter = false
        model.returnToTitle()
        #expect(model.canContinue)       // the new game was autosaved at once
        model.requestNewCharter()
        #expect(model.confirmingNewCharter)
        #expect(model.route == .title)
    }

    @Test func leavingSetupRefreshesContinue() throws {
        let store = InMemoryGameStore()
        let model = AppModel(store: store, saves: InMemorySaveSlots())
        model.startNewCharter(houses: [.varn, .solace], hazards: false)
        model.returnToTitle()
        #expect(model.canContinue)
        try store.clear()   // as when that game ends
        model.openSetup()
        model.closeSetup()
        #expect(model.route == .title)
        #expect(!model.canContinue)
    }
}
