# AI Opponents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five offline, non-LLM computer opponents (Cadet, Pilot, Navigator, Commander, Admiral) to Spanning the Stars, selectable per House at setup, measured by headless bot-vs-bot tournaments.

**Architecture:** The rules already live in `StarsCore` as a `Sendable` value-type engine (`GameEngine`, `GameState`), so the AI calls the engine directly (brief option A). New code sits in `Sources/StarsCore/AI/`: a redacted `PlayerView`, a stateless `Bot` protocol, one heuristic agent with five settings, a determinized Monte Carlo search for Level 5, and a tournament library with a `Tournament` command-line target. `GameSession` drives bot seats off the main actor.

**Tech Stack:** Swift 6.4 (tools 6.2, language mode 6), SwiftPM, Swift Testing (`import Testing`), SwiftUI, macOS 26. No dependencies.

**Spec:** `docs/spanning-the-stars-ai-plan.md` (the brief). It is planning input: its Requirements section binds, the rest is opinion that the Decisions log below adopts, adapts or rejects.

## Decisions log

Entries marked **BIG** change existing game code or depart from the brief in a way worth reading first.

### Integration

| # | Decision | Options considered | Reason |
| --- | --- | --- | --- |
| D1 | **Option A: use the existing API directly.** | A (direct), B (adapter and snapshot), C (extract rules) | Rules are already apart from SwiftUI in `StarsCore`. `GameEngine` and `GameState` are `Sendable` structs (`GameEngine.swift:1`, `GameState.swift:21`), so `var copy = state` is the simulation copy. `legalActions`, `apply`, `finalScores` and `ranking` already exist and `FuzzTests` already plays 500 random headless games. An adapter would add a layer with nothing to adapt. |
| D2 | The one missing capability, "see only what that player may see", is a new `PlayerView` struct built from `GameState`. Bots receive only the view. | Pass `GameState` and trust bots; module boundary; view struct | `GameState` holds every hand, the deck order, the RNG and the seed. A view type makes the no-cheating rule a property of the type a bot is handed. |
| D3 | AI code lives inside the `StarsCore` target under `Sources/StarsCore/AI/`, not in a new `StarsAI` target. | Separate target; folder in `StarsCore` | `GameSession` (in `StarsCore`) must drive bots, so a separate target would need a dependency cycle or a protocol indirection. Level 5 must also build `GameState` values, whose memberwise init is internal. |
| D4 | **BIG (existing code).** `PlayerKind` gains `case bot(BotLevel)` (`House.swift:15`). | New field elsewhere; extend the enum | The enum exists for this purpose and has only `.human`. Synthesized `Codable` keeps old saves decoding. No existing `switch` over it. |
| D5 | **BIG (existing code).** `GameConfig` gains `public var kinds: [PlayerKind]?` with an init default of `nil` (`GameState.swift:1`), and `GameEngine.newGame` reads it (`GameEngine.swift:11`). `nil` means all human. | Set kinds on the state after `newGame`; non-optional field | The replay log rebuilds a game from its `start` line through `newGame(config)` (`ReplayLog.swift:171`), so kinds must travel in the config. Optional so that saves and logs written before this change still decode. Existing call sites compile unchanged. |
| D6 | **BIG (existing code).** `isClosed` (`Payments.swift:58`) and `claimBlocker` (`Engine+Claim.swift:3`) each gain a free-function overload taking plain values (`laneOwner`, `playerCount`, `beacons`, `hazards`); the existing functions delegate to them. Behavior is unchanged. | Reimplement the two checks against `PlayerView`; refactor | The brief forbids a second copy of the rules. The planner and view need "can this seat claim this lane" without a full `GameState`. |
| D7 | **BIG (existing code).** `GameSession` gains a `Screen.botTurn(player:)` case, bot scheduling, and two init parameters with defaults (`botDelay`, `botDeadline`). With exactly one human seat, the hand-off screen is skipped. | Drive bots from the SwiftUI layer; drive from the session | The session already owns state, autosave and the replay log, and is unit-tested headless. With one human nobody else needs to look away, so the hand-off is friction. With two or more humans hand-offs stay as they are. All-human games are untouched. |
| D8 | **BIG (existing code).** `SetupView.onBegin`, `AppModel.startNewCharter`, `GameView` and `StatusBar` change to carry and show seat kinds. `startNewCharter` keeps its existing parameters and adds `kinds:` with a default. | none | Needed for the difficulty picker. Existing tests call `startNewCharter(houses:hazards:)` and keep compiling. |

Existing types touched, complete list: `PlayerKind`, `GameConfig`, `GameEngine.newGame`, `isClosed`, `GameEngine.claimBlocker`, `GameSession`, `AppModel`, `SetupView`, `GameView`, `StatusBar`, `Package.swift`. Nothing in `Rules/Scoring.swift`, the draw, claim, contract or turn logic changes.

### Design

| # | Decision | Options considered | Reason |
| --- | --- | --- | --- |
| D9 | One heuristic agent for Levels 1 to 4, determinized Monte Carlo on top for Level 5. | Brief's recommendation; one Monte Carlo search for all levels | The game is hidden-information with chance and up to 5 players, and the strategy splits into route planning, card gathering and blocking, which a scored agent handles. A search-only ladder needs fast playouts before Level 1 exists and weak levels play oddly. |
| D10 | **BIG (departs from brief).** Bots are stateless: a decision is a pure function of `(PlayerView, rng)`. The rng for a decision is derived from the game seed, the log length, the phase and the seat. | Stateful bots holding a plan between turns; stateless | A whole bot game is then a pure function of the config, so replays, saves, resumes and Level 5 playouts need no bot memory. The cost is D11. The seed is mixed into the rng by the driver; the bot never sees the seed. |
| D11 | **BIG (departs from brief).** "Level 2 follows its first plan and never replans" is adapted. Every level recomputes its routes from the current board each turn. Pilot is weaker because it plans each Contract separately, has no scoring of alternatives, no endgame mode and a 15% mistake rate. | Keep a frozen plan; recompute | A claimed lane can never be reclaimed in this game (`Engine+Claim.swift:4`), so a bot that keeps a blocked plan stalls for the rest of the game, which looks broken, not weak. It also follows from D10. |
| D12 | `PlayerView` omits the seed and shows the Salvage Heap, Supply Depot and Contract deck as counts only. | Expose salvage contents as a face-up discard pile; counts only | The seed determines every shuffle. The UI shows only "Salvage Heap N" (`ExchangeView.swift:16`), so counts are what a human in the seat sees. Assumption logged: salvage contents are hidden. |
| D13 | Level 5 budget is a playout count (reproducible) with an optional wall-clock deadline of 1.5 s used only in the app. Headless tournaments pass no deadline. | Time budget only; count only; both | A time budget alone makes results depend on machine load, which breaks "same seed, same game". The deadline keeps the app responsive on slow machines. A decision cut short by the deadline is the one case that is not reproducible. |
| D14 | Level 5 uses the same sampled hidden states for every candidate move (common random numbers), and skips search during setup Contract picks, where it uses the Commander heuristic. | Independent samples per candidate | With a few playouts per move, sharing samples removes most of the noise in the comparison. Setup picks have many seats still to choose, which is expensive to sample for little gain. |
| D15 | Information-set MCTS: rejected. | Determinized Monte Carlo; ISMCTS | More code and tuning for an uncertain gain; revisit only if Level 5 misses its target. |
| D16 | `BotSettings.weights` is a struct of named `Double` fields (`BotWeights`), not `[String: Double]`. `searchBudget: Duration` becomes `playouts: Int`. | Brief's shape | The compiler catches a misspelled weight. See D13 for the budget. |
| D17 | The tournament runner is a library (`Sources/StarsCore/AI/Tournament.swift`) plus an executable target `Tournament`, run in release: `swift run -c release Tournament ...`. Games run in parallel across cores; results do not depend on scheduling because game `g` is seeded `seed + g`. | Test target only; CLI | Thousands of games in a debug test target would be slow, and the brief's example is a CLI. |
| D18 | A tie for first counts as `1 / (Houses tied)` of a win for each tied House. Seats rotate each game so every level sits in every seat equally. | Ties as losses | Shared victories are a real outcome (`Scoring.swift:86`); the engine also picks the first player at random. |
| D19 | The L5 vs L4 ladder match uses 400 games, not 2,000. | 2,000 | Each Level 5 game runs thousands of playouts. 400 games gives a 95% interval of about plus or minus 5 points, enough to check a 60% target. The game count is a starting value in the brief. |
| D20 | A ladder check passes when the higher level's observed win rate is at least `target - 2 * sqrt(target * (1 - target) / n)`. | Raw threshold | A 200-game run of a level that truly wins 65% falls below 65% half the time. The rule tolerates two standard errors and no more. |
| D21 | **BIG (departs from brief).** There is no CI and no git remote in this repo. The plan adds `scripts/ladder.sh` (the short ladder) and `.github/workflows/ci.yml` that runs `swift test` and the short ladder. The workflow cannot be verified from here. | Skip CI; add an unverified workflow | The brief asks for a short ladder in CI. The script is verified locally; the workflow is the closest workable reading. |
| D22 | Milestone order is adapted: session and UI wiring (brief Milestone 8) starts right after the bot driver exists and runs alongside the level work. Parallel tasks run in separate git worktrees and are merged by the controller. | Brief's order | The wiring depends only on the driver, not on bot strength. Two subagents building in one working tree break each other's compiles, so each gets a worktree. |
| D23 | All-bot games (no human seat) are allowed at setup. | Require one human | Harmless, and it is how "a full game at each level runs in the app" gets checked. |
| D24 | Hill-climbing script for weights: not planned. Each level task tunes by hand for at most 6 rounds; a miss after that is recorded here and in `docs/ai-results.md`. | Build the script up front | The brief offers it only for when manual tuning stalls. |
| D25 | The planner is a new int-indexed `MapGraph`, not the existing `shortestPath` (`MapGeometry.swift:4`). | Reuse `shortestPath` | The existing function ignores ownership and scans string-keyed dictionaries; playouts call the planner thousands of times. The existing function stays as it is for Contract values. |
| D26 | Commit messages start with the milestone, for example `M3: add route planner`. No `Co-Authored-By` trailer (user's global rule). Work happens on branch `feature/ai-opponents`. | none | Brief's process requirement plus the user's standing instruction. |

### Outcomes recorded during execution

| # | Decision | Options considered | Reason |
| --- | --- | --- | --- |
| D27 | **BIG (target gap).** Commander vs Navigator is accepted at 57.3% over 2,000 two-player games, against the 60% target (95% interval 55.1% to 59.5%). | Keep tuning; add a new rule; accept and record | Six tuning rounds were spent and five landed within noise, so the weights the plan names have little leverage. The likely cure, holding back from starting the final round when behind, is a design change outside this plan. Commander is still stronger than Navigator at two players. |
| D28 | **BIG (finding).** At four players Commander is not stronger than Navigator (42.0% against 46.1% over 1,000 games; 42.9% against 45.6% with hazards). Recorded, not fixed. | Retune `block` on 4-House games; scale blocking by House count; record | Found by the last tournament runs, after the tuning budget was spent. The blocking weight (2.0) was tuned on two-player games, where denying the one rival is always good. A follow-up should scale or drop the block term when there are three or more Houses and add the hold-back rule from D27. |
| D29 | Execution ran in Claude Code sessions in cmux panels (one to three at a time, parallel work in git worktrees, commits cherry-picked onto `feature/ai-opponents`), not in background subagents. Each task still got a fresh-context implementer and a fresh-context review. | Background subagents | The user stopped the first background subagent and pointed at the panels. |
| D30 | Tasks added or split during execution: Task 13 (load-independent main-actor test, Codex and log usable on bot turns, status chip slack) from review findings; Task 12 split into 12a (ladder code, script, CI) and 12b (runs and write-up, done by the controller). Per-level legality tests play 60 games, not 300. | none | Review findings needed an owner; the split let idle panels work; the debug suite was already slow and the 2,000-game tournaments report illegal moves. |
| D32 | Task 14 (tune-up, added after the first write-up): Commander's blocking is off with 3 or more Houses and a hold-back rule was added. At four players Commander now beats Navigator (47.8% against 39.9%), closing D28. At two players it is 57.6%, so D27 stays open after six more tuning rounds. The work was halted by the owner before Admiral was re-measured, before the final tables were re-run and before any whole-branch review; everything was merged to `main` at the owner's instruction. Open items are listed in `docs/ai-opponents-handoff.md`. | Finish the tune-up first; merge now | The owner said to halt, write a handoff and merge. The full test suite passes. |
| D31 | Open after execution: the whole-branch review has not run; the debug test suite takes about 5.5 minutes because some tests play full Admiral games; nobody has yet played a game in the running app (bot seats are covered by `GameSession` tests only); the CI workflow is unverified (no remote). | none | The usage window ran out before the final review. |

### Brief recommendations

| Recommendation | Verdict | Note |
| --- | --- | --- |
| One rule-based agent for Levels 1 to 4, Monte Carlo for Level 5 | Adopted | D9 |
| Alternative: Monte Carlo for all five levels | Rejected | D9 |
| Prefer option A, then B, then C | Adopted | D1 |
| `Bot` protocol: view and RNG in, move out | Adopted | Plus an optional deadline, D13 |
| Level 1: legal moves, light bias to scoring now | Adopted | |
| Dijkstra planner, owned links free, rival links blocked | Adopted | D25 |
| Resource tracker; Level 2 never replans | Adapted | D11 |
| Weighted action scorer, replanning, endgame mode at Level 3 | Adopted | |
| Opponent model, blocking, end-of-game bonus at Level 4 | Adopted | The bonus is the Great Span Award |
| Determinized Monte Carlo, top moves from Level 4, Level 3 playouts | Adopted | D13, D14 |
| Information-set MCTS | Rejected | D15 |
| Difficulty picker and thinking delay | Adopted | D7, D8 |
| Milestone order and parallel work | Adapted | D22 |
| `BotSettings` shape | Adapted | D16 |
| Level names and the table of starting values | Adopted | Tournament results overrule the numbers |
| Softmax temperature and mistake rate | Adopted | A mistake drops one Contract from the bot's goals for that decision |
| Tournament runner as a command-line target | Adopted | D17 |
| Report: win rate with 95% interval, average score, Contracts completed and failed, game length | Adopted | |
| Ladder targets at 2,000 games | Adapted | D19, D20 |
| Hill-climbing script | Deferred | D24 |
| 4-player mixed-level games | Adopted | Task 12 |
| Results in `docs/ai-results.md`, 200-game ladder in CI | Adapted | D21 |
| Run AI off the main actor on `Sendable` data | Adopted | D7 |

## Milestone 0: the game as the code defines it

**Pieces**

- 110 Resource Cards: 12 each of 8 colors (red, purple, black, white, blue, green, yellow, orange) and 14 Quantum Cores, which are wild (`Cards.swift:1`, `Cards.swift:46`).
- 45 Anchor Beacons per House (`House.swift:22`). 5 Houses (`House.swift:1`).
- 33 Concord Contracts on the standard map, each a pair of systems with a value of `d + max(0, d - 12) / 4`, `d` being the shortest path length (`Board.swift:45`, `GalaxyMap+Standard.swift`).
- Great Span Award: 10 points (`Scoring.swift:77`).

**Board** (`GalaxyMap+Standard.swift`): 36 star systems in 4 regions and 78 lanes. Lane lengths: 26 of length 2, 26 of length 3, 14 of length 4, 8 of length 5, 4 of length 6. 11 lanes are open (any one color); the rest have a fixed color. 26 lanes form 13 twin pairs. 6 Spectrum and 6 Gravity Well lanes matter only when the Frontier Hazards variant is on.

**Setup** (`GameEngine.swift:6`): shuffle, deal 4 cards per House, offer 4 Contracts per House, pick the first player at random, fill the 5-slot Exchange. Each House in seat order keeps at least 2 of its 4 offered Contracts; the returns are shuffled to the bottom of the Contract deck (`Engine+Contracts.swift:2`).

**Actions** (`Action.swift:12`, legal lists from `GameEngine.legalActions`, `GameEngine.swift:67`)

- `drawBlind`, `drawExchange(slot:)`: take 2 cards. A face-up Core must be the first card and ends the turn. The Exchange refills at once and resets when it shows 3 or more Cores (`Engine+Draw.swift`).
- `claim(laneID:payment:)`: pay cards equal to the lane's length in its color, Cores wild; open lanes take any one color. Hazards on: Spectrum lanes need all-different colors, Gravity Well lanes cost one card fewer and one beacon more (`Payments.swift:12`, `Payments.swift:18`). Blockers: lane taken, twin closed with 3 or fewer Houses, own twin, too few beacons (`Engine+Claim.swift:3`).
- `drawContracts` then `keepContracts`: draw up to 3, keep at least 1 (`Engine+Contracts.swift:24`).
- `pass`: only when nothing else is legal (`Engine+Turn.swift:27`).

**Scoring** (`Payments.swift:1`, `Scoring.swift:66`): lane points on claiming are 1, 2, 4, 7, 10, 15 for lengths 1 to 6. At the end: plus each fulfilled Contract's value, minus each unfulfilled one, plus 10 for every House tied for the longest trail. Ranking ties fall to Contracts completed, then the Award, then a shared victory (`Scoring.swift:86`).

**Game end** (`Engine+Turn.swift:5`): when a House ends a turn with 2 or fewer beacons, every House including that one takes one more turn. The game also ends when every House passes in one round.

**Hidden and public information.** Hidden from other seats: hand contents, Contracts held, the order of the Supply Depot and the Contract deck, the Salvage Heap's contents (D12), other seats' setup offers, the RNG and the seed. Public: the Exchange, every count (hands, Contracts, beacons, decks, salvage), scores, lane owners, the final-round countdown, and the event log, which names cards taken from the Exchange but not blind draws (`Action.swift:28`, `StatusBar.swift:43`, `ExchangeView.swift:16`).

**Player counts:** 2 to 5 (`SetupView.swift:74`). Twin lanes close with 2 or 3 Houses (`Payments.swift:58`).

**Where rules and state live:** all rules in `Sources/StarsCore` (structs and free functions). `GameSession` (`@MainActor @Observable` class, `GameSession.swift:5`) wraps a `GameState` for the UI.

## Global Constraints

- No LLM, no network, no new package dependencies.
- A bot receives a `PlayerView` and an rng, never a `GameState`, the seed or the engine's RNG.
- Bots choose only from `PlayerView.legalActions`, which comes from `GameEngine.legalActions`. No rule is reimplemented outside `Sources/StarsCore/Rules` and `Sources/StarsCore/Engine`.
- All 165 existing tests keep passing with no edits to their assertions.
- A bot game is a pure function of its `GameConfig`: same config, same final state.
- Bot thinking runs off the main actor.
- Every task follows red, green, commit. Commit subjects start with the milestone tag given in the task (`M1:` to `M8:`). No `Co-Authored-By` trailer.
- Tournaments run in release mode: `swift run -c release Tournament ...`.
- Level names: 1 Cadet, 2 Pilot, 3 Navigator, 4 Commander, 5 Admiral.
- Every number called a starting value may be tuned; the final value and the tournament result that justified it go in `docs/ai-results.md`.
- Tuning is capped at 6 rounds per level. A target still missed is recorded in `docs/ai-results.md` and the Decisions log, and the work continues.

## Review Focus

1. A save or autosave resumed while it is a bot's turn: the bot must start moving, not wait at a hand-off screen. (Task 10)
2. A new game or a loaded save arriving while a bot is still thinking: the stale decision must be dropped, never applied to the new state. (Task 10)
3. Saves and replay logs written before this change (no `kinds` key): they must load as all-human games. (Task 2)
4. Thin legal-move lists: only `pass` legal, the Contract deck empty, the Depot and Salvage both empty, Frontier Hazards on. Every level must return a legal action. (Tasks 2, 3, 5, 9)
5. Seat mixes: no human at all, and one human with four bots. No bot hand is ever shown, and the Final Review appears. (Tasks 10, 11)

## File structure

| File | Responsibility | Task |
| --- | --- | --- |
| `Sources/StarsCore/AI/PlayerView.swift` | What one seat may see | 1 |
| `Sources/StarsCore/AI/Bot.swift` | `Bot`, `BotLevel`, `RandomBot`, `BotRoster`, `BotDriver` | 2 |
| `Sources/StarsCore/AI/HeadlessGame.swift` | `playGame` | 2 |
| `Sources/StarsCore/AI/HeuristicBot.swift` | `BotSettings`, `BotWeights`, the Level 1 to 4 agent | 3, 5, 6, 8 |
| `Sources/StarsCore/AI/Tournament.swift` | `runMatch`, statistics | 3 |
| `Sources/Tournament/main.swift` | CLI | 3, 12 |
| `Sources/StarsCore/AI/RoutePlanner.swift` | `MapGraph`, `Route` | 4 |
| `Sources/StarsCore/AI/CardNeeds.swift` | Resource tracker | 5 |
| `Sources/StarsCore/AI/OpponentModel.swift` | Contract guesses, block values | 7 |
| `Sources/StarsCore/AI/SearchBot.swift` | `determinize`, Level 5 | 9 |
| `Tests/StarsCoreTests/AI/*.swift` | One test file per source file above | all |
| `docs/ai-results.md` | Tournament results per milestone | 3 onward |

## Execution waves

| Wave | Tasks | Notes |
| --- | --- | --- |
| 1 | 1, then 2 | In order on the feature branch |
| 2 | 3, 4, 10 in parallel | Separate worktrees; no shared files |
| 3 | 5, 11 in parallel | 5 needs 3 and 4; 11 needs 10 |
| 4 | 6, 7 in parallel | 7 touches only `OpponentModel.swift` and its test |
| 5 | 8, then 9, then 12 | In order |

---

### Task 1: PlayerView and value-based rule checks (M1)

**Files:**
- Create: `Sources/StarsCore/AI/PlayerView.swift`
- Modify: `Sources/StarsCore/Rules/Payments.swift:57-61`, `Sources/StarsCore/Engine/Engine+Claim.swift:2-9`
- Test: `Tests/StarsCoreTests/AI/PlayerViewTests.swift`

**Interfaces:**
- Consumes: `GameState`, `GameEngine.legalActions`, `beaconCost`.
- Produces:

```swift
// Payments.swift
public func isClosed(_ lane: Lane, laneOwner: [Int: Int], playerCount: Int) -> Bool
public func claimBlocker(_ lane: Lane, seat: Int, laneOwner: [Int: Int], playerCount: Int,
                         beacons: Int, hazards: Bool) -> RuleError?

// PlayerView.swift
public struct SeatView: Sendable, Equatable {
    public let house: House
    public let kind: PlayerKind
    public let handCount: Int
    public let contractCount: Int
    public let beacons: Int
    public let score: Int
    public let lanes: [Int]
}

public struct PlayerView: Sendable, Equatable {
    public let seat: Int
    public let hazards: Bool
    public let seats: [SeatView]
    public let current: Int
    public let firstPlayer: Int
    public let phase: TurnPhase          // offered ids emptied when seat != current
    public let hand: Hand                // this seat only
    public let contracts: [Int]          // this seat only
    public let exchange: [Card?]
    public let depotCount: Int
    public let salvageCount: Int
    public let contractDeckCount: Int
    public let laneOwner: [Int: Int]
    public let finalTurnsRemaining: Int?
    public let consecutivePasses: Int
    public let log: [GameEvent]
    public let legalActions: [Action]    // engine.legalActions(state) when seat == current, else []
    public init(state: GameState, seat: Int, engine: GameEngine)
    /// The engine's claim guard for any seat, from public information.
    public func claimBlocker(_ lane: Lane, seat: Int) -> RuleError?
}
```

- [ ] **Step 1: Write the failing tests** in `PlayerViewTests.swift` (suite `PlayerViewTests`, `@testable import StarsCore`). Helper `playing(seed:houses:)`: `GameEngine(map: .standard).newGame(...)`, then each seat keeps its first 2 offered Contracts.

```swift
@Test func viewShowsOwnSecretsAndPublicCounts() {
    let s = playing(seed: 7, houses: [.varn, .solace, .meridian])
    let v = PlayerView(state: s, seat: s.current, engine: engine)
    #expect(v.hand == s.players[s.current].hand)
    #expect(v.contracts == s.players[s.current].contracts)
    #expect(v.seats.map(\.handCount) == s.players.map(\.hand.total))
    #expect(v.seats.map(\.contractCount) == s.players.map(\.contracts.count))
    #expect(v.depotCount == s.depot.count && v.salvageCount == s.salvage.count)
    #expect(v.contractDeckCount == s.contractDeck.count)
    #expect(v.exchange == s.exchange && v.laneOwner == s.laneOwner)
    #expect(v.legalActions == engine.legalActions(s))
}

@Test func viewIsBlindToHiddenState() {
    // Two true states that differ only in what seat 0 cannot see give equal views.
    let a = playing(seed: 7, houses: [.varn, .solace])
    var b = a
    let seat = a.current, other = 1 - seat
    b.depot.reverse()
    b.contractDeck.reverse()
    b.rng = SeededRNG(seed: 999)
    b.config.seed = 12345
    // swap the rival's hand with the same number of depot cards
    let n = b.players[other].hand.total
    var newHand = Hand()
    for _ in 0..<n { newHand.add(b.depot.removeLast()) }
    for (card, count) in b.players[other].hand.counts { b.depot += Array(repeating: card, count: count) }
    b.players[other].hand = newHand
    b.players[other].contracts = Array(b.contractDeck.suffix(b.players[other].contracts.count))
    #expect(PlayerView(state: a, seat: seat, engine: engine) == PlayerView(state: b, seat: seat, engine: engine))
}

@Test func nonCurrentSeatSeesNoOffersOrActions() {
    let s = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 3))
    let v = PlayerView(state: s, seat: 1, engine: engine)   // seat 0 is choosing
    #expect(v.phase == .setupContracts(offered: []))
    #expect(v.legalActions.isEmpty)
}

@Test func viewClaimBlockerMatchesEngine() {
    // On every state of a 200-action random game, for every lane and seat:
    // view.claimBlocker(lane, seat:) == engine.claimBlocker(lane, seat:, in: state)
}
```

Write `viewClaimBlockerMatchesEngine` in full with the loop the comment describes (seed 11, 4 Houses, hazards on, moves picked with `SeededRNG(seed: 11)`).

- [ ] **Step 2: Run** `swift test --filter PlayerViewTests`. Expected: does not compile, `PlayerView` undefined.
- [ ] **Step 3: Add the two free functions to `Payments.swift`** and make `isClosed(_:in:)` and `GameEngine.claimBlocker(_:seat:in:)` call them. The check order in `claimBlocker` stays: taken, closed, own twin, beacons.
- [ ] **Step 4: Implement `PlayerView`** as specified. `PlayerView` has no stored `GameState` and no seed.
- [ ] **Step 5: Run** `swift test`. Expected: all tests pass, including the 165 existing ones.
- [ ] **Step 6: Commit** `M1: add PlayerView and value-based claim checks`.

### Task 2: Bot protocol, seat kinds, driver and headless games (M1)

**Files:**
- Create: `Sources/StarsCore/AI/Bot.swift`, `Sources/StarsCore/AI/HeadlessGame.swift`
- Modify: `Sources/StarsCore/Model/House.swift:15`, `Sources/StarsCore/Model/GameState.swift:1-11`, `Sources/StarsCore/Engine/GameEngine.swift:11-13`
- Test: `Tests/StarsCoreTests/AI/HeadlessGameTests.swift`

**Interfaces:**
- Consumes: `PlayerView` (Task 1).
- Produces:

```swift
public enum BotLevel: Int, CaseIterable, Codable, Sendable {
    case cadet = 1, pilot, navigator, commander, admiral
    public var displayName: String   // "Cadet", "Pilot", "Navigator", "Commander", "Admiral"
}
public enum PlayerKind: Codable, Sendable, Equatable { case human, bot(BotLevel) }

// GameConfig
public var kinds: [PlayerKind]?      // nil = all human; else one per House
public init(houses: [House], frontierHazards: Bool, seed: UInt64, kinds: [PlayerKind]? = nil)

public protocol Bot: Sendable {
    /// Must return a member of `view.legalActions`. `deadline` is a hint only search bots use.
    func chooseAction(view: PlayerView, rng: inout SeededRNG, deadline: ContinuousClock.Instant?) -> Action
}
public struct RandomBot: Bot { public init() }   // uniform over legal actions

/// Builds the bot for each level once per map. Task 2 returns RandomBot for every level;
/// Tasks 3, 5, 6, 8 and 9 replace one level each.
public struct BotRoster: Sendable {
    public init(engine: GameEngine)
    public func bot(_ level: BotLevel) -> any Bot
}

public struct BotDecision: Sendable, Equatable {
    public let action: Action
    public let substituted: Bool   // the bot's choice was illegal and legalActions[0] was used
}
public struct BotDriver: Sendable {
    public init(engine: GameEngine)
    public init(engine: GameEngine, roster: BotRoster)
    /// nil when the game is over or the current seat is human.
    public func decide(_ state: GameState, deadline: ContinuousClock.Instant? = nil) -> BotDecision?
}
/// rng for one decision: SplitMix seeded from seed, log length, phase tag (0 to 3) and current seat.
func decisionRNG(_ state: GameState) -> SeededRNG

public struct GameResult: Sendable, Equatable {
    public let state: GameState
    public let scores: [FinalScore]
    public let ranking: [[Int]]
    public let turns: Int            // decisions taken in the awaitingAction phase
    public let illegalMoves: Int
}
/// Every seat must be a bot. Stops after maxActions as a guard.
public func playGame(config: GameConfig, engine: GameEngine, driver: BotDriver? = nil,
                     maxActions: Int = 5000) -> GameResult
```

`decide` builds the `PlayerView` for the current seat, and passes the bot only that view and the derived rng.

- [ ] **Step 1: Write the failing tests** in `HeadlessGameTests.swift`:

```swift
private func bots(_ n: Int, _ level: BotLevel, seed: UInt64, hazards: Bool = false) -> GameConfig {
    GameConfig(houses: Array(House.allCases.prefix(n)), frontierHazards: hazards, seed: seed,
               kinds: Array(repeating: .bot(level), count: n))
}

@Test func thousandRandomBotGamesFinishLegally() {
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

@Test func driverIgnoresHumansAndFinishedGames() {
    let engine = GameEngine(map: .standard)
    let human = engine.newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false, seed: 1))
    #expect(BotDriver(engine: engine).decide(human) == nil)
    let done = playGame(config: bots(2, .cadet, seed: 1), engine: engine).state
    #expect(BotDriver(engine: engine).decide(done) == nil)
}

@Test func illegalChoiceIsSubstitutedAndCounted() {
    // A roster whose bot always returns .pass: playGame still finishes, illegalMoves > 0.
}

@Test func kindsReachTheState() {
    let s = GameEngine(map: .standard).newGame(GameConfig(houses: [.varn, .solace], frontierHazards: false,
                                                          seed: 1, kinds: [.human, .bot(.navigator)]))
    #expect(s.players.map(\.kind) == [.human, .bot(.navigator)])
}

@Test func configWithoutKindsStillDecodes() throws {   // Review Focus 3
    let old = #"{"houses":["varn","solace"],"frontierHazards":false,"seed":9}"#
    let c = try JSONDecoder().decode(GameConfig.self, from: Data(old.utf8))
    #expect(c.kinds == nil)
    #expect(GameEngine(map: .standard).newGame(c).players.allSatisfy { $0.kind == .human })
}

@Test func oldSavedStateStillDecodes() throws {        // Review Focus 3
    // Encode an all-human GameState, strip the "kinds" key from the JSON text if present,
    // decode, and expect equality with the original.
}
```

For `illegalChoiceIsSubstitutedAndCounted`, give `BotRoster` an internal init taking `(BotLevel) -> any Bot` and use it from the test. Write both commented tests in full.

- [ ] **Step 2: Run** `swift test --filter HeadlessGameTests`. Expected: does not compile.
- [ ] **Step 3: Add `BotLevel`, extend `PlayerKind` and `GameConfig`, read `config.kinds` in `newGame`** (`config.kinds?[i] ?? .human`).
- [ ] **Step 4: Implement `Bot.swift` and `HeadlessGame.swift`** as specified.
- [ ] **Step 5: Run** `swift test`. Expected: all pass.
- [ ] **Step 6: Commit** `M1: add bot protocol, seat kinds, driver and headless games`.

### Task 3: Level 1 Cadet and the tournament runner (M2)

**Files:**
- Create: `Sources/StarsCore/AI/HeuristicBot.swift`, `Sources/StarsCore/AI/Tournament.swift`, `Sources/Tournament/main.swift`, `docs/ai-results.md`
- Modify: `Package.swift` (add `.executableTarget(name: "Tournament", dependencies: ["StarsCore"])`), `Sources/StarsCore/AI/Bot.swift` (`BotRoster.bot(.cadet)` only)
- Test: `Tests/StarsCoreTests/AI/CadetTests.swift`, `Tests/StarsCoreTests/AI/TournamentTests.swift`

**Interfaces:**
- Consumes: Task 2.
- Produces:

```swift
public struct BotWeights: Sendable, Equatable {
    public var pointsNow = 1.0     // per Standing point scored by a claim
    public var draw = 1.0          // base score of a card draw
    public var newContracts = -2.0 // base score of drawContracts
    // later tasks add fields
}
public struct BotSettings: Sendable, Equatable {
    public var usesPlanner: Bool
    public var usesScorer: Bool
    public var usesOpponentModel: Bool
    public var temperature: Double   // softmax temperature, in Standing points
    public var mistakeRate: Double
    public var playouts: Int         // 0 = no search
    public var weights: BotWeights
    public static func level(_ level: BotLevel) -> BotSettings
}
public struct HeuristicBot: Bot {
    public init(settings: BotSettings, map: GalaxyMap)
    /// Every legal action with its score, best first; ties broken by position in view.legalActions.
    public func scoredActions(view: PlayerView) -> [(action: Action, score: Double)]
}
/// Picks by softmax over scores; temperature 0 picks the first best.
func softmaxPick(_ scored: [(action: Action, score: Double)], temperature: Double, rng: inout SeededRNG) -> Action

public struct BotStats: Sendable, Equatable {
    public let level: BotLevel
    public let samples: Int              // seat-games played at this level
    public let wins: Double              // win credit, D18
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
/// `levels` has one entry per seat. Game g uses seed `seed &+ UInt64(g)` and rotates `levels` left by g.
public func runMatch(levels: [BotLevel], games: Int, seed: UInt64, hazards: Bool = false,
                     engine: GameEngine = GameEngine(map: .standard)) async -> MatchReport
public func wilson(wins: Double, n: Int) -> (low: Double, high: Double)
```

Cadet starting values: `usesPlanner`, `usesScorer`, `usesOpponentModel` all false; temperature 2.0; mistake rate 0; scores: a claim scores `pointsNow * lanePoints(length)`, a draw scores `draw`, `drawContracts` scores `newContracts`, `keepContracts(ids)` scores `-Double(ids.count)`, `pass` scores 0.

CLI: `swift run -c release Tournament --a 3 --b 2 --games 2000 --players 2 --seed 42 [--hazards]` seats alternate a, b, a, b up to `--players`. `--levels 1,2,3,4` gives one level per seat instead. Defaults: games 2000, players 2, seed 42. It prints `MatchReport.text`. Unknown flags or a level outside 1 to 5 print usage and exit 2.

- [ ] **Step 1: Write the failing tests.**

```swift
// CadetTests
@Test func cadetPrefersBigClaimsAtZeroTemperature() {
    // View where a length-6 claim and draws are legal: scoredActions.first is the length-6 claim.
}
@Test func cadetMustPassWhenOnlyPassIsLegal() { /* a state where legalActions == [.pass]; chooses .pass */ }
@Test func softmaxAtZeroTemperatureIsArgmax() { /* scores [1, 5, 5]: returns the first 5 */ }
@Test func softmaxSpreadsAtHighTemperature() { /* 2000 picks at temperature 100 from two actions: each above 40% */ }
@Test func thousandCadetGamesFinishLegally() { /* as Task 2's test, expects illegalMoves == 0 for 1000 seeds */ }

// TournamentTests
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
```

Write each commented test in full. Build the pass-only state by emptying the depot, salvage, Exchange and Contract deck of a playing state and giving the current seat an empty hand.

- [ ] **Step 2: Run** `swift test --filter "CadetTests|TournamentTests"`. Expected: does not compile.
- [ ] **Step 3: Implement `HeuristicBot.swift`** (Cadet behavior only) and register it for `.cadet` in `BotRoster`.
- [ ] **Step 4: Implement `Tournament.swift`** with a task group over games, then the CLI and the `Package.swift` target.
- [ ] **Step 5: Run** `swift test`. Expected: all pass.
- [ ] **Step 6: Run** `swift run -c release Tournament --a 1 --b 1 --games 1000 --players 2 --seed 42`. Expected: exit 0, 0 illegal moves, win rate 50% for the single level.
- [ ] **Step 7: Create `docs/ai-results.md`** with a heading per milestone and the Step 6 output under "M2".
- [ ] **Step 8: Commit** `M2: add Cadet bot and tournament runner`.

### Task 4: Route planner (M3)

**Files:**
- Create: `Sources/StarsCore/AI/RoutePlanner.swift`
- Test: `Tests/StarsCoreTests/AI/RoutePlannerTests.swift`

**Interfaces:**
- Consumes: `claimBlocker(_:seat:laneOwner:playerCount:beacons:hazards:)` from Task 1.
- Produces:

```swift
public struct Route: Sendable, Equatable {
    public let toClaim: [Int]   // unowned lane ids on the path, in path order from `from`
    public let cost: Int        // sum of the lengths of toClaim lanes not in `free`
}
public struct MapGraph: Sendable {
    public let map: GalaxyMap
    public init(map: GalaxyMap)
    /// Cheapest way for `seat` to join the two systems. Lanes the seat owns cost 0, lanes in `free`
    /// cost 0, any lane the seat could not claim (taken by a rival, closed, or twin of its own lane)
    /// is blocked. Beacons are ignored. nil when no route exists. Ties: fewer lanes to claim, then
    /// the lower lane ids. A route between already joined systems is Route(toClaim: [], cost: 0).
    public func route(from: String, to: String, seat: Int, laneOwner: [Int: Int], playerCount: Int,
                      free: Set<Int> = []) -> Route?
}
```

- [ ] **Step 1: Write the failing tests** on `GalaxyMap.tiny` (`Tests/StarsCoreTests/TestMaps.swift`: A-B 2, B-C 3, C-D twins 1 and 1 (ids 2, 3), D-E 3, E-F 3, A-F 6, B-E 4).

```swift
let g = MapGraph(map: .tiny)

@Test func shortestRouteOnAnEmptyBoard() {
    #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [:], playerCount: 2) == Route(toClaim: [0, 1, 2], cost: 6))
}
@Test func blockedLinkForcesADetour() {
    // Rival owns B-C: A to D goes A-B, B-E, E-D.
    #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [1: 1], playerCount: 2) == Route(toClaim: [0, 7, 4], cost: 9))
}
@Test func ownedLinksCostNothing() {
    #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [0: 0, 1: 0], playerCount: 2) == Route(toClaim: [2], cost: 1))
}
@Test func impossibleGoalIsNil() {
    // Rival owns A-B and A-F: A is cut off.
    #expect(g.route(from: "A", to: "D", seat: 0, laneOwner: [0: 1, 6: 1], playerCount: 2) == nil)
}
@Test func closedTwinIsBlockedWithThreeOrFewerHouses() {
    // Rival owns twin 2; with 2 Houses twin 3 is closed, so C-D is unreachable directly.
    #expect(g.route(from: "C", to: "D", seat: 0, laneOwner: [2: 1], playerCount: 2) == Route(toClaim: [1, 7, 4], cost: 10))
    #expect(g.route(from: "C", to: "D", seat: 0, laneOwner: [2: 1], playerCount: 4) == Route(toClaim: [3], cost: 1))
}
@Test func alreadyJoinedCostsZero() {
    #expect(g.route(from: "A", to: "C", seat: 0, laneOwner: [0: 0, 1: 0], playerCount: 2) == Route(toClaim: [], cost: 0))
}
@Test func freeLanesAreSharedBetweenGoals() {
    #expect(g.route(from: "A", to: "E", seat: 0, laneOwner: [:], playerCount: 2, free: [0, 7])?.cost == 0)
}
@Test func agreesWithTheMapsShortestPathOnAnEmptyBoard() {
    // For every contract on GalaxyMap.standard: route cost == shortestPath(map, a, b).
}
```

- [ ] **Step 2: Run** `swift test --filter RoutePlannerTests`. Expected: does not compile.
- [ ] **Step 3: Implement `MapGraph`.** Index systems to `Int` once in `init`; Dijkstra over arrays (36 nodes, a linear scan for the minimum is enough).
- [ ] **Step 4: Run** `swift test --filter RoutePlannerTests`. Expected: pass.
- [ ] **Step 5: Commit** `M3: add route planner`.

### Task 5: Resource tracker and Level 2 Pilot (M4)

**Files:**
- Create: `Sources/StarsCore/AI/CardNeeds.swift`
- Modify: `Sources/StarsCore/AI/HeuristicBot.swift`, `Sources/StarsCore/AI/Bot.swift` (`BotRoster.bot(.pilot)` only), `docs/ai-results.md`
- Test: `Tests/StarsCoreTests/AI/CardNeedsTests.swift`, `Tests/StarsCoreTests/AI/PilotTests.swift`

**Interfaces:**
- Consumes: `MapGraph.route` (Task 4), `HeuristicBot`, `BotSettings` (Task 3), `runMatch`.
- Produces:

```swift
/// What the hand still lacks for a set of wanted lanes.
public struct CardNeeds: Sendable, Equatable {
    public init(lanes: [Lane], hand: Hand, hazards: Bool)
    /// 0 when the card helps no wanted lane, up to 1 when it completes one. Cores always score above 0
    /// while any wanted lane is unpaid.
    public func value(of card: Card) -> Double
}
// HeuristicBot gains (internal): the goal list for a view
struct Goal: Equatable { let contractID: Int; let value: Int; let route: Route? }
func goals(view: PlayerView) -> [Goal]      // unfulfilled own Contracts with their routes
```

Pilot behavior (planner on, scorer off). Settings starting values: temperature 1.0, mistake rate 0.15.

- Goals: each unfulfilled Contract gets its own route (no `free` sharing). A mistake (15% of decisions) drops one random Contract from the goals for that decision.
- Wanted lanes: the union of the routes' `toClaim`.
- Claims: a claim of a wanted lane scores `wantedClaim + pointsNow * lanePoints`; other claims score as Cadet's minus `offPlanPenalty`. Among payments for one lane, the engine's first option (fewest Cores) scores highest.
- Draws: an Exchange card scores `draw + cardNeed * needs.value(of: card)`; a blind draw scores `draw + cardNeed * blindShare`, with `blindShare` a fixed 0.3.
- `drawContracts`: scores `newContracts` (negative).
- `keepContracts`: at setup and after a draw, score a subset by the sum over kept Contracts of `value - keepCostWeight * route cost`, impossible routes counting as `-value`; the minimum legal subset size wins ties.
- New `BotWeights` fields and starting values: `wantedClaim = 6`, `offPlanPenalty = 4`, `cardNeed = 3`, `keepCostWeight = 0.5`.

- [ ] **Step 1: Write the failing tests.**

```swift
// CardNeedsTests (hand and lanes built by hand on GalaxyMap.tiny)
@Test func neededColorScoresAboveUnneeded() { /* wanted lane A-B red 2, empty hand: value(.resource(.red)) > 0, value(.resource(.blue)) == 0 */ }
@Test func satisfiedLaneNeedsNothing() { /* hand holds 2 red: value(.resource(.red)) == 0 */ }
@Test func coreHelpsWhileAnythingIsUnpaid() { /* value(.core) > 0; with every wanted lane paid, value(.core) == 0 */ }
@Test func openLaneWantsTheColorHeldMost() { /* wanted lane B-C open 3, hand 2 green: value(.green) > value(.red) */ }

// PilotTests (HeuristicBot(settings: .level(.pilot)) with mistakeRate and temperature set to 0)
@Test func claimsAWantedLaneItCanPayFor() { /* Contract A-C on tiny, hand 2 red: chooses claim of lane 0 */ }
@Test func drawsTheExchangeCardItNeeds() { /* hand empty, Exchange holds one red: chooses that slot */ }
@Test func keepsTheContractsItCanReach() { /* setup offer on tiny where one Contract is cut off: it is not kept */ }
@Test func neverPicksAnIllegalAction() { /* 300 Pilot-only games, hazards alternating, 2 to 5 Houses: illegalMoves == 0 */ }
@Test func pilotBeatsCadetInAShortMatch() async {
    let r = await runMatch(levels: [.pilot, .cadet], games: 60, seed: 9)
    #expect(r.stats.last!.winRate > 0.6)     // smoke check; the 2,000-game run is Step 5
}
```

- [ ] **Step 2: Run** `swift test --filter "CardNeedsTests|PilotTests"`. Expected: does not compile.
- [ ] **Step 3: Implement `CardNeeds`, then the Pilot branch of `HeuristicBot`,** and register `.pilot` in `BotRoster`. `HeuristicBot` builds its `MapGraph` once in `init`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Run** `swift run -c release Tournament --a 2 --b 1 --games 2000 --players 2 --seed 42`. Target: Pilot wins at least 75%. If it misses, tune per the Global Constraints (temperature and mistake rate first, weights one at a time).
- [ ] **Step 6: Record** the final settings and the tournament output under "M4" in `docs/ai-results.md`.
- [ ] **Step 7: Commit** `M4: add resource tracker and Pilot bot`.

### Task 6: Action scorer and Level 3 Navigator (M5)

**Files:**
- Modify: `Sources/StarsCore/AI/HeuristicBot.swift`, `Sources/StarsCore/AI/Bot.swift` (`BotRoster.bot(.navigator)` only), `docs/ai-results.md`
- Test: `Tests/StarsCoreTests/AI/NavigatorTests.swift`

**Interfaces:**
- Consumes: Task 5.
- Produces: `BotSettings.level(.navigator)`; `HeuristicBot.scoredActions` stays the entry point Task 9 relies on.

Navigator behavior (planner and scorer on). Settings starting values: temperature 0.3, mistake rate 0.05. Every score is in Standing points.

- **Joint plan:** plan Contracts in descending value, passing lanes already wanted as `free`, so routes share lanes.
- **Replanning:** routes come from the current `laneOwner` every decision, so a rival's claim on a wanted lane yields the detour. A Contract with no route is abandoned: it leaves the goals and stops attracting draws.
- **Plan progress:** a claim of a wanted lane scores `planProgress * sum over Contracts using the lane of value * lane.length / route cost before the claim`.
- **Urgency:** for a wanted lane, add `urgency * detour`, `detour` being the rise in that Contract's route cost if the lane were lost (capped at 10; an impossible detour counts as 10). Lanes of length 1 or 2 and twin lanes with 3 or fewer Houses are the usual high-detour cases.
- **Card draws:** as Pilot, with a taken face-up Core scoring `coreValue` when any wanted lane is unpaid.
- **Affordability:** when a wanted lane is payable now, claims outrank draws by at least `claimNowBonus`.
- **More Contracts:** `drawContracts` scores positive only when every held Contract is fulfilled or abandoned, the seat has at least `contractBeaconFloor` beacons and endgame mode is off.
- **Endgame mode:** on when `finalTurnsRemaining != nil` or any seat has `endgameBeacons` or fewer beacons. In it, `drawContracts` scores `-100`, claims score `pointsNow * lanePoints * endgamePointsBoost` plus plan progress only for a claim that completes a Contract this turn, and draws lose `cardNeed`.
- New `BotWeights` fields and starting values: `planProgress = 1.5`, `urgency = 0.5`, `coreValue = 4`, `claimNowBonus = 2`, `contractBeaconFloor = 15`, `endgameBeacons = 8`, `endgamePointsBoost = 1.5`.

- [ ] **Step 1: Write the failing tests** (Navigator with temperature and mistake rate 0).

```swift
@Test func replansAfterABlock() {
    // tiny map, Contract A-D, rival claims B-C (lane 1): goals(view) route becomes [0, 7, 4]
    // and with 4 black cards in hand the top action is the claim of lane 7.
}
@Test func abandonsAnImpossibleContract() {
    // rival owns lanes 0 and 6: the A-D Contract has route nil and no draw is scored for its colors.
}
@Test func sharesLanesBetweenContracts() {
    // Contracts A-C and A-D: the wanted set is [0, 1, 2], total cost 6, not 11.
}
@Test func urgentShortLaneBeatsALongerOne() {
    // Both payable; the length-1 twin whose loss forces a detour outranks an equal-progress lane.
}
@Test func endgameModeTakesPoints() {
    // A rival at 5 beacons: the top action is the highest-scoring payable claim, and drawContracts is last.
}
@Test func drawsContractsOnlyWhenGoalsAreDone() {
    // All Contracts fulfilled, 30 beacons, no endgame: drawContracts is the top action.
    // One Contract still open: it is not.
}
@Test func neverPicksAnIllegalAction() { /* 300 Navigator-only games as in Task 5 */ }
```

Write each in full; build states by starting from `newGame` on the named map and assigning `laneOwner`, `players[i].lanes`, hands and Contracts directly.

- [ ] **Step 2: Run** `swift test --filter NavigatorTests`. Expected: fail.
- [ ] **Step 3: Implement the Navigator branch** and register `.navigator`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Run** `swift run -c release Tournament --a 3 --b 2 --games 2000 --players 2 --seed 42`. Target: at least 65%. Tune if needed.
- [ ] **Step 6: Record** settings and output under "M5" in `docs/ai-results.md`.
- [ ] **Step 7: Commit** `M5: add action scorer and Navigator bot`.

### Task 7: Opponent model (M6)

**Files:**
- Create: `Sources/StarsCore/AI/OpponentModel.swift`
- Test: `Tests/StarsCoreTests/AI/OpponentModelTests.swift`

**Interfaces:**
- Consumes: `MapGraph`, `PlayerView`.
- Produces:

```swift
public struct ContractGuess: Sendable, Equatable {
    public let contractID: Int
    public let likelihood: Double
}
public struct OpponentModel: Sendable {
    public init(graph: MapGraph)
    /// Contracts the rival may hold, most likely first; likelihoods sum to 1. Excludes the viewer's own
    /// Contracts. Uses only the view: the rival's lanes, the board and the Contract list.
    public func likelyContracts(of opponent: Int, view: PlayerView) -> [ContractGuess]
    /// Standing the viewer expects to deny rivals by claiming this lane: for each rival, the sum over
    /// its 5 likeliest Contracts of likelihood * min(value, rise in that rival's route cost without
    /// the lane), an impossible route counting as the Contract's value. 0 for a lane no rival needs.
    public func blockValue(laneID: Int, view: PlayerView) -> Double
}
```

Likelihood for a Contract: proportional to `0.02 + progress^2`, `progress = (d0 - dNow) / d0`, `d0` the empty-board route cost between its systems and `dNow` the rival's current route cost (own lanes free). A Contract the rival can no longer reach gets the floor 0.02. Both 0.02 and the exponent are starting values.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func ranksTheTrueGoalInTheTopThree() {
    // Standard map. For each of 10 Contracts (ids 0, 3, 6, ... 27): give seat 1 every lane but the
    // last on that Contract's empty-board route, view from seat 0 (holding no Contracts):
    // the Contract's id is within the first 3 of likelyContracts(of: 1, view:).
}
@Test func likelihoodsSumToOneAndExcludeMyContracts() { /* sum within 1e-9 of 1; none of view.contracts listed */ }
@Test func noLanesMeansAFlatGuess() { /* rival owns nothing: all likelihoods equal */ }
@Test func blockValueIsPositiveOnTheRivalsCriticalLane() {
    // tiny map, 2 Houses: rival owns A-B; lane 1 (B-C) has blockValue > lane 6 (A-F), and lane 6 is near 0.
}
@Test func blockValueIsZeroForTakenLanes() { /* a lane already owned scores 0 */ }
```

- [ ] **Step 2: Run** `swift test --filter OpponentModelTests`. Expected: does not compile.
- [ ] **Step 3: Implement `OpponentModel`.** Cache the empty-board route cost per Contract in `init`.
- [ ] **Step 4: Run** `swift test --filter OpponentModelTests`. Expected: pass.
- [ ] **Step 5: Commit** `M6: add opponent model`.

### Task 8: Level 4 Commander (M6)

**Files:**
- Modify: `Sources/StarsCore/AI/HeuristicBot.swift`, `Sources/StarsCore/AI/Bot.swift` (`BotRoster.bot(.commander)` only), `docs/ai-results.md`
- Test: `Tests/StarsCoreTests/AI/CommanderTests.swift`

**Interfaces:**
- Consumes: Tasks 6 and 7, `greatSpan(lanes:)` (`Scoring.swift:21`).
- Produces: `BotSettings.level(.commander)`.

Commander adds to Navigator. Settings starting values: temperature 0.1, mistake rate 0.02, `usesOpponentModel` true.

- **Blocking:** every claim adds `block * model.blockValue(laneID:view:)`.
- **Great Span:** a claim adds `span * max(0, mySpanAfter - max(mySpanBefore, bestRivalSpan - spanReach))`, so growth counts once the seat is within `spanReach` of the leader. Compute rival spans once per decision.
- **Endgame timing:** endgame mode also turns on when the seat itself could end the game: its beacons minus the longest lane it can pay for now is 2 or less. Then, if the seat's projected final total (score plus fulfilled Contracts minus unfulfilled plus span bonus if leading) leads every rival's public score by `closeOutLead`, the claim that triggers the final round gains `closeOut`.
- New `BotWeights` fields and starting values: `block = 0.6`, `span = 0.5`, `spanReach = 6`, `closeOut = 5`, `closeOutLead = 10`.

- [ ] **Step 1: Write the failing tests** (temperature and mistake rate 0).

```swift
@Test func blocksARivalsCriticalLaneWhenItCostsLittle() {
    // tiny, 2 Houses, own goals fulfilled, rival owns A-B, hand pays for lane 1 and for lane 6's
    // points-equivalent alternative: lane 1 scores higher for Commander, not for Navigator.
}
@Test func extendsTheLongestSpanWhenInReach() {
    // Two payable lanes of equal length and no goals: the one that lengthens the trail wins.
}
@Test func spanTermIsZeroWhenFarBehind() { /* rival span 20, own 2: the span term adds nothing */ }
@Test func neverPicksAnIllegalAction() { /* 300 Commander-only games, 2 to 5 Houses, hazards alternating */ }
```

- [ ] **Step 2: Run** `swift test --filter CommanderTests`. Expected: fail.
- [ ] **Step 3: Implement the Commander terms** and register `.commander`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Run** `swift run -c release Tournament --a 4 --b 3 --games 2000 --players 2 --seed 42`. Target: at least 60%. Tune if needed.
- [ ] **Step 6: Record** settings and output under "M6" in `docs/ai-results.md`.
- [ ] **Step 7: Commit** `M6: add Commander bot`.

### Task 9: Level 5 Admiral search (M7)

**Files:**
- Create: `Sources/StarsCore/AI/SearchBot.swift`
- Modify: `Sources/StarsCore/AI/Bot.swift` (`BotRoster.bot(.admiral)` only), `docs/ai-results.md`
- Test: `Tests/StarsCoreTests/AI/SearchBotTests.swift`

**Interfaces:**
- Consumes: `HeuristicBot.scoredActions`, `OpponentModel.likelyContracts`, `PlayerView`, `GameEngine`.
- Produces:

```swift
/// A full state consistent with the view, hidden parts sampled. Precondition: the phase is not setupContracts.
/// Guarantee: PlayerView(state: result, seat: view.seat, engine: engine) == view.
func determinize(_ view: PlayerView, engine: GameEngine, model: OpponentModel, rng: inout SeededRNG) -> GameState

public struct SearchBot: Bot {
    public init(settings: BotSettings, engine: GameEngine)
}
```

Sampling: the unknown cards are the standard deck minus the viewer's hand and the Exchange; shuffle them and deal the rivals' hands (by `handCount`), the Salvage Heap (by `salvageCount`) and the Depot (by `depotCount`). Each rival's Contracts are drawn without replacement from the Contracts the viewer does not hold and was not offered, weighted by `likelyContracts`; the rest, shuffled, form the Contract deck (`contractDeckCount` of them). `pendingOffers` and `setupReturns` are empty, `config.seed` and `rng` come from the bot rng.

Search, starting values `candidates = 6`, `playouts = 48` (so 8 sampled states), playout policy Navigator settings with temperature 0.3 and mistake rate 0:

1. In `setupContracts`, or when one action is legal, return the Commander choice.
2. Take the top `candidates` of the Commander's `scoredActions`, keeping at most one claim per lane.
3. Sample `playouts / candidates` states once. For each candidate and each state: copy, apply the candidate, play to the end with the playout policy for every seat, and score `winCredit + (myTotal - bestRivalTotal) / 100` from `finalScores` and `ranking`.
4. Return the candidate with the best mean; ties go to the Commander's order.
5. Check `deadline` between playouts; when it passes, stop and use the means so far (candidates with no playout keep the Commander's order behind those with one).

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func determinizedStateMatchesTheView() {
    // 30 mid-game states (Navigator games stopped after 40, 80 and 120 actions, 2 to 4 Houses):
    // PlayerView(state: determinize(view, ...), seat:, engine:) == view, and the state has 110 cards
    // and 33 Contracts in total.
}
@Test func leakTestHiddenStateDoesNotChangeTheMove() {
    // State a mid-game; state b = a with the rival's hand swapped for depot cards, the depot and
    // Contract deck reordered and the rival's Contracts replaced (as in Task 1's blind test).
    // Same config seed. BotDriver(engine:).decide(a)?.action == decide(b)?.action for an Admiral seat.
}
@Test func sameViewAndSeedGiveTheSameMove() { /* two calls with equal rng: equal actions */ }
@Test func returnsALegalActionInEveryPhase() { /* setup pick, first draw, second draw, contract choice, pass-only */ }
@Test func staysWithinItsDeadline() {
    // deadline = now + 1.5 s on a 4-House mid-game state: the call returns within 1.75 s.
}
@Test func admiralGamesFinishLegally() { /* 6 Admiral-vs-Commander games with playouts 12: illegalMoves == 0 */ }
```

- [ ] **Step 2: Run** `swift test --filter SearchBotTests`. Expected: does not compile.
- [ ] **Step 3: Implement `determinize`, then `SearchBot`,** and register `.admiral` with `BotSettings.level(.admiral)` (`playouts = 48`, temperature 0, mistake rate 0).
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Measure** one release-mode Admiral decision on a 2-House mid-game state (`swift run -c release Tournament --a 5 --b 4 --games 4 --players 2 --seed 1` and the per-decision time it prints, adding a `--timing` flag that prints mean and maximum seconds per Admiral decision). Target: maximum under 1.5 s. If over, lower `playouts`; if far under, raise it. Speeding up the playout policy (for example caching routes within a decision) is in scope; changing rules code is not.
- [ ] **Step 6: Run** `swift run -c release Tournament --a 5 --b 4 --games 400 --players 2 --seed 42`. Target: at least 60% (D19). Tune `candidates`, `playouts` and the playout temperature if needed.
- [ ] **Step 7: Record** settings, timing and output under "M7" in `docs/ai-results.md`.
- [ ] **Step 8: Commit** `M7: add Admiral search bot`.

### Task 10: GameSession drives bot seats (M8)

**Files:**
- Modify: `Sources/StarsCore/Session/GameSession.swift`
- Test: `Tests/StarsCoreTests/AI/BotSessionTests.swift`

**Interfaces:**
- Consumes: `BotDriver.decide` (Task 2).
- Produces:

```swift
// GameSession
public enum Screen: Equatable { case handoff(player: Int), playing, finalReview, botTurn(player: Int) }
public init(config: GameConfig, map: GalaxyMap = .standard, store: GameStore = InMemoryGameStore(),
            saves: SaveSlots = InMemorySaveSlots(), log: ReplayLog? = nil,
            botDelay: Duration = .milliseconds(800), botDeadline: Duration = .seconds(1.5))
// load(id:...) and resume(...) gain the same two parameters with the same defaults.
/// Returns once no bot move is pending: a human is to act or the game is over.
public func waitForBots() async
```

Behavior:

- After every state change (init, `perform`, `loadGame`, `load`, `resume`) with the game not over: if the current seat is a bot, `screen = .botTurn(player:)` and a bot move starts. Otherwise, with exactly one human seat, `screen = .playing`; with two or more humans, `.handoff(player:)` exactly as today.
- A bot move: capture the state, compute `driver.decide(state, deadline: now + botDeadline)` in a detached task, wait until at least `botDelay` has passed since the move started, then, on the main actor, apply the action only if the session's state still equals the captured state. The action goes through the same path as `perform` (replay log, autosave, events, final review).
- `perform` stays ignored unless `screen == .playing`, so a human cannot act on a bot's turn.
- `recentEvents` at a hand-off holds every event since the previous human seat finished, so bot moves between two humans are listed.
- `loadGame` and deinit cancel a pending bot move.

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite`, sessions built with `botDelay: .zero`).

```swift
@Test func oneHumanSkipsTheHandoff() async {
    let s = GameSession(config: config([.human, .bot(.cadet)]), botDelay: .zero)
    await s.waitForBots()
    #expect(s.screen == .playing)
    #expect(s.state.players[s.state.current].kind == .human)
}
@Test func botsPlayUntilTheHumanMustAct() async {
    // Human keeps 2 Contracts; after waitForBots the bot has kept its own and the phase is no longer setup.
}
@Test func allBotGameReachesTheFinalReview() async {   // Review Focus 5
    for level in [BotLevel.cadet, .pilot, .navigator, .commander] {
        let s = GameSession(config: config([.bot(level), .bot(level)]), botDelay: .zero)
        await s.waitForBots()
        #expect(s.screen == .finalReview)
    }
}
@Test func admiralGameReachesTheFinalReview() async {
    // [.bot(.admiral), .bot(.cadet)] with botDeadline .milliseconds(40): finalReview.
}
@Test func twoHumansStillGetHandoffs() async {
    // [.human, .human, .bot(.cadet)]: after seat 0's setup pick the screen is .handoff(player: 1);
    // after the bot's turn the hand-off's recentEvents include the bot's events.
}
@Test func humanCannotActOnABotTurn() async { /* perform during .botTurn leaves the state unchanged */ }
@Test func resumingOnABotTurnStartsTheBot() async {    // Review Focus 1
    // Save mid-game with a bot to move (store shared), GameSession.resume(...): after waitForBots the
    // current seat is human or the game is over.
}
@Test func loadingDuringABotMoveDropsTheStaleDecision() async {   // Review Focus 2
    // botDelay 200 ms. Start a bot move, loadGame(another save) at once, waitForBots:
    // the state descends from the loaded save (its log is a prefix of the session's log).
}
@Test func mainActorStaysFreeWhileABotThinks() async {
    // Admiral vs Admiral, botDeadline 300 ms. A main-actor task sleeps 10 ms in a loop and records
    // the longest gap between wake-ups while 4 bot actions are applied: under 250 ms.
}
@Test func botMovesAreLoggedForReplay() async {
    // With a ReplayLog: after an all-Cadet game, ReplayLog.replay(url, engine:) equals the final state.
}
```

- [ ] **Step 2: Run** `swift test --filter BotSessionTests`. Expected: does not compile.
- [ ] **Step 3: Implement the session changes.** Use a generation counter or state equality for staleness.
- [ ] **Step 4: Run** `swift test`. Expected: all pass, including `SessionTests`, `SavesTests`, `ReplayLogTests` and the screen tests unchanged.
- [ ] **Step 5: Commit** `M8: drive bot seats from GameSession off the main actor`.

### Task 11: Difficulty picker and bot turns on screen (M8)

**Files:**
- Modify: `Sources/SpanningTheStars/Views/SetupView.swift`, `Sources/SpanningTheStars/App.swift:53-57,171`, `Sources/SpanningTheStars/Views/GameView.swift:23-58`, `Sources/SpanningTheStars/Views/StatusBar.swift:28-52`
- Test: `Tests/SpanningTheStarsTests/BotScreenTests.swift`

**Interfaces:**
- Consumes: Task 10, `BotLevel.displayName`.
- Produces:

```swift
// SetupView
let onBegin: (_ houses: [House], _ hazards: Bool, _ kinds: [PlayerKind]) -> Void
/// Kinds in seat order for the chosen Houses; a House with no choice is human.
static func kinds(for houses: [House], choices: [House: PlayerKind]) -> [PlayerKind]
/// Picker rows: "Human", then "Cadet (Level 1)" to "Admiral (Level 5)".
static let kindOptions: [(label: String, kind: PlayerKind)]

// AppModel
func startNewCharter(houses: [House], hazards: Bool, kinds: [PlayerKind]? = nil)

// GameView
/// Banner text for a bot's turn, for example "House Ashkar (Navigator) is plotting its move".
static func botBanner(_ player: PlayerState) -> String?   // nil for a human
```

Screen rules:

- Setup: each chosen House row shows a menu picker of `kindOptions`, default "Human". Unchosen Houses show none.
- `.botTurn`: the board is shown without blur and without hit testing, the hand and Contracts trays stay hidden (`Secrets.shown` is already false off `.playing`), the claim sheet closes, and the banner sits at the top of the map.
- Status bar: a bot's chip shows its level name under the House name.

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite`).

```swift
@Test func kindsFollowSeatOrderAndDefaultToHuman() {
    #expect(SetupView.kinds(for: [.varn, .meridian, .paleFleet],
                            choices: [.paleFleet: .bot(.admiral), .solace: .bot(.cadet)])
            == [.human, .human, .bot(.admiral)])
}
@Test func pickerOffersHumanAndFiveLevels() {
    #expect(SetupView.kindOptions.map(\.label) == ["Human", "Cadet (Level 1)", "Pilot (Level 2)",
        "Navigator (Level 3)", "Commander (Level 4)", "Admiral (Level 5)"])
}
@Test func startingWithKindsCreatesBotSeats() {
    // AppModel with in-memory stores: startNewCharter(houses: [.varn, .solace], hazards: false,
    // kinds: [.human, .bot(.pilot)]) gives session.state.players.map(\.kind) == [.human, .bot(.pilot)].
}
@Test func bannerNamesTheHouseAndLevel() {
    #expect(GameView.botBanner(player(.ashkar, .bot(.navigator))) == "House Ashkar (Navigator) is plotting its move")
    #expect(GameView.botBanner(player(.ashkar, .human)) == nil)
}
@Test func botHandsStayHidden() {      // Review Focus 5
    #expect(Secrets(screen: .botTurn(player: 1), player: playerWithCards).shown == false)
    #expect(Secrets(screen: .botTurn(player: 1), player: playerWithCards).hand == Hand())
}
```

- [ ] **Step 2: Run** `swift test --filter BotScreenTests`. Expected: does not compile.
- [ ] **Step 3: Implement** the setup picker, `startNewCharter`, the bot-turn board state and banner, and the status chip line. Match the existing panel and font styling.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Build the app** with `swift build`. Expected: no warnings from the changed files.
- [ ] **Step 6: Commit** `M8: add difficulty picker and bot turn display`.

### Task 12: Ladder, crowded boards, CI and results (M8)

**Files:**
- Modify: `Sources/StarsCore/AI/Tournament.swift`, `Sources/Tournament/main.swift`, `docs/ai-results.md`, this plan's Decisions log
- Create: `scripts/ladder.sh`, `.github/workflows/ci.yml`
- Test: `Tests/StarsCoreTests/AI/TournamentTests.swift`

**Interfaces:**
- Consumes: all levels, `runMatch`.
- Produces:

```swift
public struct LadderRung: Sendable, Equatable {
    public let higher: BotLevel
    public let lower: BotLevel
    public let target: Double        // 0.75, 0.65, 0.60, 0.60
    public let games: Int
    public let winRate: Double
    public let passed: Bool          // winRate >= ladderFloor(target:games:)
}
public func ladderFloor(target: Double, games: Int) -> Double   // target - 2 * sqrt(target * (1 - target) / games)
/// The four neighbor matches, 2 Houses. The Admiral rung plays games / 5.
public func runLadder(games: Int, seed: UInt64) async -> [LadderRung]
```

CLI: `swift run -c release Tournament --ladder --games 2000 --seed 42` prints one line per rung and exits 1 if any rung fails. `scripts/ladder.sh` runs it with `--games 200`. The workflow runs `swift test` then `scripts/ladder.sh` on `macos-26`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func ladderFloorAllowsTwoStandardErrors() {
    #expect(abs(ladderFloor(target: 0.75, games: 2000) - 0.7306) < 0.0005)
    #expect(abs(ladderFloor(target: 0.65, games: 200) - 0.5825) < 0.0005)
}
@Test func ladderHasFourRungsWithTheBriefsTargets() async {
    let rungs = await runLadder(games: 10, seed: 1)
    #expect(rungs.map(\.target) == [0.75, 0.65, 0.60, 0.60])
    #expect(rungs.map(\.higher) == [.pilot, .navigator, .commander, .admiral])
    #expect(rungs.map(\.games) == [10, 10, 10, 2])
}
```

- [ ] **Step 2: Run** `swift test --filter TournamentTests`. Expected: does not compile.
- [ ] **Step 3: Implement** `ladderFloor`, `runLadder`, the `--ladder` flag, `scripts/ladder.sh` (executable) and the workflow file.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Run** `scripts/ladder.sh`. Expected: exit 0.
- [ ] **Step 6: Run the full ladder:** `swift run -c release Tournament --ladder --games 2000 --seed 42`. Record every rung under "Final ladder" in `docs/ai-results.md`.
- [ ] **Step 7: Run crowded boards:** `swift run -c release Tournament --levels 1,2,3,4 --games 1000 --seed 42`, the same with `--hazards`, and `--levels 2,3,4,5 --games 100 --seed 42`. Expected: 0 illegal moves, win rates rising with level. Record under "4-player mixed levels".
- [ ] **Step 8: Update the Decisions log** in this plan: for any rung that missed its target, add a row naming the gap and the cause found; tick the brief's Definition of done items that hold.
- [ ] **Step 9: Commit** `M8: add ladder check, CI workflow and final results`.

## Definition of done (from the brief)

- [x] The plan's opening section lists the game's real pieces and rules, each pointing to the code it came from
- [x] The Decisions log names the integration option, its reason, and every existing type it touches
- [x] The Decisions log marks each recommendation as adopted, adapted or rejected, with a reason
- [ ] Every requirement holds, including the leak test and an unblocked UI
- [ ] All five levels are selectable in game setup and play full games without errors
- [x] The ladder tournament meets the targets, or the Decisions log explains the gap
- [ ] The full test suite passes, and a short ladder runs in CI
