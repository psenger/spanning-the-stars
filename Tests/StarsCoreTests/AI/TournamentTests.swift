import Testing
@testable import StarsCore

/// The standard bots with a 6-playout Admiral, so a debug run plays no full-strength Admiral game.
private let smallDriver: BotDriver = {
    let engine = GameEngine(map: .standard)
    let roster = BotRoster { level in
        var settings = BotSettings.level(level)
        guard level == .admiral else { return HeuristicBot(settings: settings, map: engine.map) }
        settings.playouts = 6
        return SearchBot(settings: settings, engine: engine)
    }
    return BotDriver(engine: engine, roster: roster)
}()

@Suite struct TournamentTests {
    @Test func wilsonIntervalMatchesKnownValue() {
        let ci = wilson(wins: 150, n: 200)       // 75%
        #expect(abs(ci.low - 0.6858) < 0.001 && abs(ci.high - 0.8050) < 0.001)
    }

    @Test func matchIsReproducibleAndBalanced() async {
        let a = await runMatch(levels: [.cadet, .cadet], games: 40, seed: 5)
        let b = await runMatch(levels: [.cadet, .cadet], games: 40, seed: 5)
        #expect(a == b)
        #expect(a.stats.count == 1 && a.stats[0].samples == 80)
        #expect(abs(a.stats[0].wins - 40) < 0.0001)     // win credit sums to one per game
        #expect(a.illegalMoves == 0 && a.avgTurns > 0)
    }

    @Test func reportNamesEveryMetric() async {
        let text = await runMatch(levels: [.cadet, .cadet], games: 4, seed: 1).text
        for word in ["Cadet", "win rate", "95% CI", "avg score", "completed", "failed", "avg turns"] {
            #expect(text.contains(word))
        }
    }

    @Test func mixedLevelsGetOneRowEachAndShareTheWins() async {
        let r = await runMatch(levels: [.pilot, .cadet, .pilot], games: 12, seed: 9, hazards: true)
        #expect(r.games == 12)
        #expect(r.stats.map(\.level) == [.cadet, .pilot])   // ascending
        #expect(r.stats.map(\.samples) == [12, 24])
        #expect(abs(r.stats.reduce(0) { $0 + $1.wins } - 12) < 0.0001)
        for s in r.stats {
            #expect(abs(s.winRate - s.wins / Double(s.samples)) < 0.0001)
            #expect(s.ciLow <= s.winRate && s.winRate <= s.ciHigh)
            #expect(s.avgContractsCompleted >= 0 && s.avgContractsFailed >= 0)
        }
        #expect(r.text.contains("Cadet") && r.text.contains("Pilot"))
    }

    @Test func matchGamesUseSeedPlusIndexAndRotateSeats() async {
        // One game at seed 6 is game 1 of a match at seed 5, with the levels rotated left by 1.
        let engine = GameEngine(map: .standard)
        let config = GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 6,
                                kinds: [.bot(.cadet), .bot(.pilot)])
        let game1 = playGame(config: config, engine: engine)
        let game0 = playGame(config: GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 5,
                                                kinds: [.bot(.pilot), .bot(.cadet)]), engine: engine)
        let r = await runMatch(levels: [.pilot, .cadet], games: 2, seed: 5)
        #expect(abs(r.avgTurns - Double(game0.turns + game1.turns) / 2) < 0.0001)
        let cadetScore = Double(game0.scores[1].total + game1.scores[0].total) / 2
        #expect(abs(r.stats[0].avgScore - cadetScore) < 0.0001)
    }

    @Test func zeroGamesGiveAnEmptyReport() async {
        let r = await runMatch(levels: [.cadet, .pilot], games: 0, seed: 3)
        #expect(r.stats.isEmpty)
        #expect(r.games == 0 && r.avgTurns == 0 && r.illegalMoves == 0)
        #expect(r.text.contains("0 games") && !r.text.contains("nan"))
    }

    @Test func ladderFloorAllowsTwoStandardErrors() {
        #expect(abs(ladderFloor(target: 0.75, games: 2000) - 0.7306) < 0.0005)
        #expect(abs(ladderFloor(target: 0.65, games: 200) - 0.5825) < 0.0005)
    }

    @Test func ladderHasFourRungsWithTheBriefsTargets() async {
        let rungs = await runLadder(games: 10, seed: 1, driver: smallDriver)
        #expect(rungs.map(\.target) == [0.75, 0.65, 0.60, 0.60])
        #expect(rungs.map(\.higher) == [.pilot, .navigator, .commander, .admiral])
        #expect(rungs.map(\.lower) == [.cadet, .pilot, .navigator, .commander])
        #expect(rungs.map(\.games) == [10, 10, 10, 2])
        for rung in rungs {
            #expect((0...1).contains(rung.winRate))
            #expect(rung.passed == (rung.winRate >= ladderFloor(target: rung.target, games: rung.games)))
        }
    }

    @Test func aRungWithNoGamesDoesNotPass() async {
        let admiral = await runLadder(games: 4, seed: 1)[3]      // 4 / 5 is no games
        #expect(admiral.games == 0 && admiral.winRate == 0 && !admiral.passed)
    }
}
