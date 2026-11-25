import Foundation

public struct BotStats: Sendable, Equatable {
    public let level: BotLevel
    public let samples: Int              // seat-games played at this level
    public let wins: Double              // win credit: a tie for first is shared equally
    public let winRate: Double
    public let ciLow: Double             // 95% Wilson interval
    public let ciHigh: Double
    public let avgScore: Double
    public let avgContractsCompleted: Double
    public let avgContractsFailed: Double
}

public struct MatchReport: Sendable, Equatable {
    public let stats: [BotStats]         // one per distinct level, ascending
    public let games: Int
    public let avgTurns: Double          // per game, all seats
    public let illegalMoves: Int
    public var text: String              // the printed table
}

/// 95% Wilson score interval for `wins` out of `n`.
public func wilson(wins: Double, n: Int) -> (low: Double, high: Double) {
    guard n > 0 else { return (0, 0) }
    let z = 1.96, count = Double(n), p = wins / count
    let denominator = 1 + z * z / count
    let center = (p + z * z / (2 * count)) / denominator
    let half = z * (p * (1 - p) / count + z * z / (4 * count * count)).squareRoot() / denominator
    return (center - half, center + half)
}

/// One seat's outcome in one game.
private struct SeatResult: Sendable {
    let level: BotLevel
    let credit: Double
    let score: Int
    let completed: Int
    let failed: Int
}

private struct GameSummary: Sendable {
    let seats: [SeatResult]
    let turns: Int
    let illegalMoves: Int
}

/// `levels` has one entry per seat. Game g uses seed `seed &+ UInt64(g)` and rotates `levels` left by g.
/// `driver` replaces the standard bots; it must be built on `engine`.
public func runMatch(levels: [BotLevel], games: Int, seed: UInt64, hazards: Bool = false,
                     engine: GameEngine = GameEngine(map: .standard),
                     driver: BotDriver? = nil) async -> MatchReport {
    precondition(!levels.isEmpty, "runMatch needs at least one level")
    precondition(levels.count <= House.allCases.count, "runMatch seats at most \(House.allCases.count) levels")
    precondition(games >= 0, "runMatch cannot play a negative number of games")
    let driver = driver ?? BotDriver(engine: engine)
    let houses = Array(House.allCases.prefix(levels.count))
    // Results are stored by game index and summed in order, so scheduling cannot change the report.
    var summaries = [GameSummary?](repeating: nil, count: games)
    await withTaskGroup(of: (Int, GameSummary).self) { group in
        for g in 0..<games {
            group.addTask {
                let seated = levels.indices.map { levels[($0 + g) % levels.count] }
                let config = GameConfig(houses: houses, frontierHazards: hazards, seed: seed &+ UInt64(g),
                                        kinds: seated.map { .bot($0) })
                let r = playGame(config: config, engine: engine, driver: driver)
                let winners = r.ranking[0]
                let seats = seated.indices.map { i in
                    SeatResult(level: seated[i],
                               credit: winners.contains(i) ? 1 / Double(winners.count) : 0,
                               score: r.scores[i].total,
                               completed: r.scores[i].contractsCompleted,
                               failed: r.state.players[i].contracts.count - r.scores[i].contractsCompleted)
                }
                return (g, GameSummary(seats: seats, turns: r.turns, illegalMoves: r.illegalMoves))
            }
        }
        for await (g, summary) in group { summaries[g] = summary }
    }

    let played = summaries.compactMap { $0 }
    // No games, no rows: an average over zero seat-games would be NaN.
    let stats = (games == 0 ? [] : BotLevel.allCases.filter(levels.contains)).map { level in
        let seats = played.flatMap(\.seats).filter { $0.level == level }
        let n = Double(seats.count)
        let wins = seats.reduce(0) { $0 + $1.credit }
        let ci = wilson(wins: wins, n: seats.count)
        return BotStats(level: level, samples: seats.count, wins: wins, winRate: wins / n,
                        ciLow: ci.low, ciHigh: ci.high,
                        avgScore: Double(seats.reduce(0) { $0 + $1.score }) / n,
                        avgContractsCompleted: Double(seats.reduce(0) { $0 + $1.completed }) / n,
                        avgContractsFailed: Double(seats.reduce(0) { $0 + $1.failed }) / n)
    }
    let avgTurns = games == 0 ? 0 : Double(played.reduce(0) { $0 + $1.turns }) / Double(games)
    let illegalMoves = played.reduce(0) { $0 + $1.illegalMoves }

    var lines = [
        "\(games) games, \(levels.count) players, seed \(seed), hazards \(hazards ? "on" : "off")",
        "seats: " + levels.map(\.displayName).joined(separator: ", "),
        "level      samples  win rate  95% CI          avg score  completed  failed",
    ]
    for s in stats {
        let name = s.level.displayName.padding(toLength: 10, withPad: " ", startingAt: 0)
        let ci = String(format: "%.1f%% - %.1f%%", s.ciLow * 100, s.ciHigh * 100)
            .padding(toLength: 15, withPad: " ", startingAt: 0)
        lines.append(String(format: "%@ %7d  %7.1f%%  %@ %9.1f  %9.2f  %6.2f", name, s.samples,
                            s.winRate * 100, ci, s.avgScore, s.avgContractsCompleted, s.avgContractsFailed))
    }
    lines.append(String(format: "avg turns %.1f, illegal moves %d", avgTurns, illegalMoves))
    return MatchReport(stats: stats, games: games, avgTurns: avgTurns, illegalMoves: illegalMoves,
                       text: lines.joined(separator: "\n"))
}

/// One neighbor match of the ladder: `higher` against `lower`, 2 Houses.
public struct LadderRung: Sendable, Equatable {
    public let higher: BotLevel
    public let lower: BotLevel
    public let target: Double        // 0.75, 0.65, 0.60, 0.60
    public let games: Int
    public let winRate: Double       // of `higher`
    public let passed: Bool          // winRate >= ladderFloor(target:games:), and at least one game
}

/// The lowest win rate that still passes: `target` less two standard errors at `games` games.
public func ladderFloor(target: Double, games: Int) -> Double {
    target - 2 * (target * (1 - target) / Double(games)).squareRoot()
}

/// The four neighbor matches, 2 Houses. The Admiral rung plays games / 5. `driver` replaces the
/// standard bots on the standard map.
public func runLadder(games: Int, seed: UInt64, driver: BotDriver? = nil) async -> [LadderRung] {
    let targets = [0.75, 0.65, 0.60, 0.60]
    var rungs: [LadderRung] = []
    for (i, target) in targets.enumerated() {
        let lower = BotLevel.allCases[i], higher = BotLevel.allCases[i + 1]
        let n = higher == .admiral ? games / 5 : games
        let report = await runMatch(levels: [higher, lower], games: n, seed: seed, driver: driver)
        let winRate = report.stats.first { $0.level == higher }?.winRate ?? 0
        rungs.append(LadderRung(higher: higher, lower: lower, target: target, games: n, winRate: winRate,
                                passed: n > 0 && winRate >= ladderFloor(target: target, games: n)))
    }
    return rungs
}
