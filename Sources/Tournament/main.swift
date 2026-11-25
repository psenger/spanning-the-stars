import Foundation
import StarsCore

let usage = """
    usage: Tournament --a <1-5> --b <1-5> [--games 2000] [--players 2] [--seed 42] [--hazards] [--timing]
           Tournament --levels 1,2,3,4 [--games 2000] [--seed 42] [--hazards] [--timing]
           Tournament --ladder [--games 2000] [--seed 42]
    --a and --b alternate over the seats: a, b, a, b up to --players (2 to 5).
    --levels gives one level per seat (2 to 5 seats) and overrides --a, --b and --players.
    --ladder plays each level against the one below it, 2 Houses, and exits 1 if any rung
    misses its target by more than two standard errors. The Admiral rung plays --games / 5.
    --timing plays the match's games again one at a time and prints the mean and maximum seconds
    per Admiral decision.
    """

func fail() -> Never {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

var a: BotLevel?, b: BotLevel?, levels: [BotLevel]?
var games = 2000, players = 2, seed: UInt64 = 42, hazards = false, ladder = false, timing = false

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    // Flags that take no value.
    switch flag {
    case "--hazards": hazards = true; continue
    case "--ladder": ladder = true; continue
    case "--timing": timing = true; continue
    default: break
    }
    guard !args.isEmpty else { fail() }
    let value = args.removeFirst()
    func level(_ text: Substring) -> BotLevel {
        guard let raw = Int(text), let level = BotLevel(rawValue: raw) else { fail() }
        return level
    }
    switch flag {
    case "--a": a = level(value[...])
    case "--b": b = level(value[...])
    case "--levels": levels = value.split(separator: ",", omittingEmptySubsequences: false).map(level)
    case "--games":
        guard let n = Int(value), n > 0 else { fail() }
        games = n
    case "--players":
        guard let n = Int(value) else { fail() }
        players = n
    case "--seed":
        guard let n = UInt64(value) else { fail() }
        seed = n
    default: fail()
    }
}

if ladder {
    let rungs = await runLadder(games: games, seed: seed)
    for r in rungs {
        let floor = ladderFloor(target: r.target, games: r.games)
        let name = "\(r.higher.displayName) vs \(r.lower.displayName)"
            .padding(toLength: 22, withPad: " ", startingAt: 0)
        print(String(format: "%@ %5d games  win rate %5.1f%%  target %2.0f%%  floor %5.1f%%  %@", name,
                     r.games, r.winRate * 100, r.target * 100, floor * 100, r.passed ? "pass" : "FAIL"))
    }
    exit(rungs.allSatisfy(\.passed) ? 0 : 1)
}

let seats: [BotLevel]
if let levels {
    seats = levels
} else if let a, let b {
    guard (2...House.allCases.count).contains(players) else { fail() }
    seats = (0..<players).map { $0.isMultiple(of: 2) ? a : b }
} else {
    fail()
}
guard (2...House.allCases.count).contains(seats.count) else { fail() }

print(await runMatch(levels: seats, games: games, seed: seed, hazards: hazards).text)

if timing {
    // One game at a time, so the other games do not slow a decision down.
    let engine = GameEngine(map: .standard), driver = BotDriver(engine: engine)
    let houses = Array(House.allCases.prefix(seats.count)), clock = ContinuousClock()
    var decisions = 0, total = Duration.zero, longest = Duration.zero
    for g in 0..<games {
        let seated = seats.indices.map { seats[($0 + g) % seats.count] }
        var state = engine.newGame(GameConfig(houses: houses, frontierHazards: hazards, seed: seed &+ UInt64(g),
                                              kinds: seated.map { .bot($0) }))
        while true {
            let isAdmiral = state.players[state.current].kind == .bot(.admiral)
            let start = clock.now
            guard let decision = driver.decide(state) else { break }
            let taken = clock.now - start
            if isAdmiral {
                decisions += 1
                total += taken
                longest = max(longest, taken)
            }
            _ = try! engine.apply(decision.action, to: &state)
        }
    }
    print(String(format: "Admiral decisions %d, mean %.3f s, max %.3f s", decisions,
                 decisions == 0 ? 0 : total / .seconds(1) / Double(decisions), longest / .seconds(1)))
}
