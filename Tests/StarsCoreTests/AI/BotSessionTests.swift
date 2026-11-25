import Foundation
import Synchronization
import Testing
@testable import StarsCore

@MainActor @Suite struct BotSessionTests {
    private func config(_ kinds: [PlayerKind], seed: UInt64 = 7) -> GameConfig {
        GameConfig(houses: Array(House.allCases.prefix(kinds.count)), frontierHazards: false, seed: seed,
                   kinds: kinds)
    }

    private func keepFirstTwo(_ s: GameSession) {
        guard case let .setupContracts(offered) = s.state.phase else { return }
        s.perform(.keepContracts(Array(offered.prefix(2))))
    }

    private func isBot(_ state: GameState) -> Bool {
        if case .bot = state.players[state.current].kind { true } else { false }
    }

    private func isSetup(_ state: GameState) -> Bool {
        if case .setupContracts = state.phase { true } else { false }
    }

    @Test func oneHumanSkipsTheHandoff() async {
        let s = GameSession(config: config([.human, .bot(.cadet)]), botDelay: .zero)
        await s.waitForBots()
        #expect(s.screen == .playing)
        #expect(s.state.players[s.state.current].kind == .human)
    }

    @Test func botsPlayUntilTheHumanMustAct() async {
        let s = GameSession(config: config([.human, .bot(.cadet)]), botDelay: .zero)
        await s.waitForBots()
        #expect(isSetup(s.state))
        keepFirstTwo(s)
        #expect(s.screen == .botTurn(player: 1))
        await s.waitForBots()
        #expect(!isSetup(s.state))
        #expect(s.state.players[0].contracts.count == 2)
        #expect(s.state.players[1].contracts.count >= 2)
        #expect(s.state.current == 0)
        #expect(s.screen == .playing)
        #expect(s.recentEvents.contains { if case .keptContracts(player: 1, _) = $0 { true } else { false } })
    }

    @Test func allBotGameReachesTheFinalReview() async {
        for level in [BotLevel.cadet, .pilot, .navigator, .commander] {
            let s = GameSession(config: config([.bot(level), .bot(level)]), botDelay: .zero)
            await s.waitForBots()
            #expect(s.screen == .finalReview, "\(level)")
            #expect(s.state.phase == .gameOver, "\(level)")
        }
    }

    @Test func admiralGameReachesTheFinalReview() async {
        let s = GameSession(config: config([.bot(.admiral), .bot(.cadet)]), botDelay: .zero,
                            botDeadline: .milliseconds(40))
        await s.waitForBots()
        #expect(s.screen == .finalReview)
    }

    @Test func twoHumansStillGetHandoffs() async {
        let s = GameSession(config: config([.human, .human, .bot(.cadet)]), botDelay: .zero)
        #expect(s.screen == .handoff(player: 0))
        s.reveal()
        keepFirstTwo(s)
        #expect(s.screen == .handoff(player: 1))
        s.reveal()
        keepFirstTwo(s)
        #expect(s.screen == .botTurn(player: 2))
        await s.waitForBots()
        guard case let .handoff(seat) = s.screen else {
            Issue.record("expected a hand-off, got \(s.screen)")
            return
        }
        #expect(s.state.players[seat].kind == .human)
        #expect(s.recentEvents.contains(.keptContracts(player: 2, count: s.state.players[2].contracts.count)))
    }

    @Test func humanCannotActOnABotTurn() async throws {
        let s = GameSession(config: config([.bot(.cadet), .human]), botDelay: .seconds(60))
        #expect(s.screen == .botTurn(player: 0))
        let before = s.state
        s.perform(try #require(s.engine.legalActions(s.state).first))
        s.reveal()
        #expect(s.state == before)
        #expect(s.screen == .botTurn(player: 0))
    }

    @Test func resumingOnABotTurnStartsTheBot() async throws {
        let store = InMemoryGameStore()
        let first = GameSession(config: config([.human, .bot(.cadet)]), store: store, botDelay: .seconds(60))
        keepFirstTwo(first)
        let saved = try #require(try store.load())
        #expect(isBot(saved))

        let resumed = try #require(GameSession.resume(store: store, saves: InMemorySaveSlots(), botDelay: .zero))
        #expect(resumed.screen == .botTurn(player: 1))
        await resumed.waitForBots()
        #expect(resumed.state.log.count > saved.log.count)
        #expect(resumed.state.phase == .gameOver || !isBot(resumed.state))
        #expect(first.state == saved)   // the first session's bot is still waiting out its delay
    }

    @Test func loadingABotTurnStartsTheBot() async throws {
        let slots = InMemorySaveSlots()
        let first = GameSession(config: config([.human, .bot(.cadet)]), saves: slots, botDelay: .seconds(60))
        keepFirstTwo(first)
        try first.saveGame(named: "bot to move", replacing: nil)
        let id = try #require(slots.list().first?.id)

        let loaded = try GameSession.load(id: id, store: InMemoryGameStore(), saves: slots, botDelay: .zero)
        #expect(loaded.screen == .botTurn(player: 1))
        await loaded.waitForBots()
        #expect(loaded.screen == .playing)
        #expect(loaded.state.current == 0)
    }

    @Test func loadingDuringABotMoveDropsTheStaleDecision() async throws {
        let slots = InMemorySaveSlots()
        let s = GameSession(config: config([.human, .bot(.cadet)]), saves: slots, botDelay: .milliseconds(200))
        try s.saveGame(named: "start", replacing: nil)
        let id = try #require(slots.list().first?.id)
        let saved = try slots.load(id: id).state

        keepFirstTwo(s)
        #expect(s.screen == .botTurn(player: 1))
        try s.loadGame(id: id)
        await s.waitForBots()
        // Long enough for the dropped move to have landed, had it not been dropped.
        try await Task.sleep(for: .milliseconds(400))
        #expect(Array(s.state.log.prefix(saved.log.count)) == saved.log)
        #expect(s.state == saved)
        #expect(s.screen == .playing)
        #expect(s.lastError == nil)   // the dropped action was never offered to the engine
    }

    /// The bot seat is a `GatedBot`, which stays inside its decision until this test, running on the
    /// main actor, releases it. Deciding off the main actor leaves the test free to see the move
    /// still pending and open the gate; deciding on it puts the bot on the main thread, which the
    /// bot reports instead of waiting for a release that could never come.
    @Test func mainActorStaysFreeWhileABotThinks() async {
        let bot = GatedBot()
        let s = GameSession(config: config([.bot(.cadet), .human]), botDelay: .zero,
                            botDeadline: .seconds(60), roster: BotRoster { _ in bot })
        let before = s.state
        var entered = bot.entered.makeAsyncIterator()
        await entered.next()
        // The bot is now mid-decision, and this line runs on the main actor.
        let onMainThread = bot.decidedOnMainThread.load(ordering: .relaxed)
        #expect(!onMainThread)
        #expect(s.state == before)
        #expect(s.screen == .botTurn(player: 0))
        bot.release()
        await s.waitForBots()
        #expect(s.state != before)
        #expect(s.screen == .playing)
    }

    @Test func botMovesAreLoggedForReplay() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("botsession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = try ReplayLog(directory: folder)
        let s = GameSession(config: config([.bot(.cadet), .bot(.cadet)]), log: log, botDelay: .zero)
        await s.waitForBots()
        #expect(s.screen == .finalReview)
        #expect(try ReplayLog.replay(log.fileURL, engine: s.engine) == s.state)
    }
}

/// Announces each decision on `entered`, then waits inside `chooseAction` until `release()` and
/// takes the first legal action. Called on the main thread it does not wait (nothing could release
/// it) and sets `decidedOnMainThread` instead.
private final class GatedBot: Bot {
    let entered: AsyncStream<Void>
    let decidedOnMainThread = Atomic(false)
    private let announce: AsyncStream<Void>.Continuation
    private let gate = DispatchSemaphore(value: 0)

    init() {
        (entered, announce) = AsyncStream.makeStream()
    }

    func release() { gate.signal() }

    func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action {
        announce.yield()
        if Thread.isMainThread {
            decidedOnMainThread.store(true, ordering: .relaxed)
        } else {
            gate.wait()
        }
        return view.legalActions[0]
    }
}
