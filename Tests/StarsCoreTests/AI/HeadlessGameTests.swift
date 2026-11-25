import Foundation
import Testing
@testable import StarsCore

private func bots(_ n: Int, _ level: BotLevel, seed: UInt64, hazards: Bool = false) -> GameConfig {
    GameConfig(houses: Array(House.allCases.prefix(n)), frontierHazards: hazards, seed: seed,
               kinds: Array(repeating: .bot(level), count: n))
}

/// Always answers `.pass`, which is illegal whenever any other action exists.
private struct PassBot: Bot {
    func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action { .pass }
}

@Suite struct HeadlessGameTests {
    @Test func thousandCadetGamesFinishLegally() {
        let engine = GameEngine(map: .standard)
        for seed in UInt64(1)...1000 {
            let r = playGame(config: bots(2 + Int(seed % 4), .cadet, seed: seed, hazards: seed.isMultiple(of: 2)),
                             engine: engine)
            #expect(r.state.phase == .gameOver, "seed \(seed)")
            #expect(r.illegalMoves == 0, "seed \(seed)")
        }
    }

    @Test func sameSeedSameGame() {
        let engine = GameEngine(map: .standard)
        let a = playGame(config: bots(3, .cadet, seed: 42), engine: engine)
        let b = playGame(config: bots(3, .cadet, seed: 42), engine: engine)
        #expect(a == b)
        #expect(a.scores.map(\.total) == b.scores.map(\.total))
        #expect(a != playGame(config: bots(3, .cadet, seed: 43), engine: engine))
    }

    @Test func resultReportsScoresRankingAndTurns() {
        let engine = GameEngine(map: .standard)
        let r = playGame(config: bots(3, .cadet, seed: 42), engine: engine)
        #expect(r.scores == finalScores(r.state, map: .standard))
        #expect(r.ranking == ranking(r.scores))
        #expect(r.turns > 0 && r.turns < r.state.log.count)
    }

    @Test func driverIgnoresHumansAndFinishedGames() {
        let engine = GameEngine(map: .standard)
        let human = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 1))
        #expect(BotDriver(engine: engine).decide(human) == nil)
        let done = playGame(config: bots(2, .cadet, seed: 1), engine: engine).state
        #expect(BotDriver(engine: engine).decide(done) == nil)
    }

    @Test func driverDecidesOnlyForBotSeats() throws {
        let engine = GameEngine(map: .standard)
        var s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 1,
                                          kinds: [.human, .bot(.cadet)]))
        let driver = BotDriver(engine: engine)
        #expect(driver.decide(s) == nil)   // seat 0 is human
        _ = try engine.apply(engine.legalActions(s)[0], to: &s)
        let d = try #require(driver.decide(s))
        #expect(engine.legalActions(s).contains(d.action))
        #expect(!d.substituted)
        #expect(driver.decide(s) == d)   // a decision is a function of the state
    }

    @Test func decisionRNGVariesWithSeedLogPhaseAndSeat() {
        let engine = GameEngine(map: .standard)
        let base = engine.newGame(bots(3, .cadet, seed: 5))
        #expect(decisionRNG(base) == decisionRNG(base))
        #expect(decisionRNG(base) != SeededRNG(seed: 5))   // never the seed itself
        var seed = base
        seed.config.seed = 6
        var log = base
        log.log.append(.exchangeReset)
        var phase = base
        phase.phase = .awaitingAction
        var seat = base
        seat.current = 1
        for other in [seed, log, phase, seat] {
            #expect(decisionRNG(other) != decisionRNG(base))
        }
    }

    @Test func illegalChoiceIsSubstitutedAndCounted() throws {
        let engine = GameEngine(map: .standard)
        let driver = BotDriver(engine: engine, roster: BotRoster { _ in PassBot() })

        let start = engine.newGame(bots(2, .cadet, seed: 1))
        let d = try #require(driver.decide(start))
        #expect(d == BotDecision(action: engine.legalActions(start)[0], substituted: true))

        let r = playGame(config: bots(2, .cadet, seed: 1), engine: engine, driver: driver)
        #expect(r.state.phase == .gameOver)
        #expect(r.illegalMoves > 0)
    }

    @Test func kindsReachTheState() {
        let s = GameEngine(map: .standard).newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false,
                                                              seed: 1, kinds: [.human, .bot(.navigator)]))
        #expect(s.players.map(\.kind) == [.human, .bot(.navigator)])
    }

    @Test func botLevelsHaveNames() {
        #expect(BotLevel.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(BotLevel.allCases.map(\.displayName) == ["Cadet", "Pilot", "Navigator", "Commander", "Admiral"])
    }

    @Test func configWithoutKindsStillDecodes() throws {   // Review Focus 3
        let old = #"{"houses":["varn","solace"],"frontierHazards":false,"seed":9}"#
        let c = try JSONDecoder().decode(GameConfig.self, from: Data(old.utf8))
        #expect(c.kinds == nil)
        #expect(GameEngine(map: .standard).newGame(c).players.allSatisfy { $0.kind == .human })
    }

    @Test func oldSavedStateStillDecodes() throws {        // Review Focus 3
        let engine = GameEngine(map: .standard)
        var original = engine.newGame(GameConfig(houses: [.varn, .solace, .meridian], frontierHazards: true, seed: 9))
        var picker = SeededRNG(seed: 9)
        for _ in 0..<40 {
            _ = try engine.apply(engine.legalActions(original).randomElement(using: &picker)!, to: &original)
        }
        var text = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        // A save written before seat kinds existed has no "kinds" key in its config.
        text = text.replacingOccurrences(of: #""kinds":null,"#, with: "")
        text = text.replacingOccurrences(of: #","kinds":null"#, with: "")
        #expect(!text.contains(#""kinds""#))
        #expect(text.contains(#""kind":{"human":{}}"#))   // the seat encoding old saves used
        let decoded = try JSONDecoder().decode(GameState.self, from: Data(text.utf8))
        #expect(decoded == original)
    }

    @Test func botConfigSurvivesCoding() throws {
        let config = GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 9,
                                kinds: [.human, .bot(.admiral)])
        let state = GameEngine(map: .standard).newGame(config)
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        #expect(decoded.config.kinds == [.human, .bot(.admiral)])
    }
}
